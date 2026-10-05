package middleware

import (
	"context"
	"log"
	"net"
	"net/http"
	"sort"
	"strings"
	"time"
)

// RequestLog writes one line per HTTP request: status, method, path, duration,
// and — once the request has been authenticated — which gym and user it
// belonged to.
//
// Without this there is no way to answer "the gym says they could not log in
// at 7pm". A failed login leaves no trace anywhere: GORM only prints slow
// queries, a rejected password writes no row, and a 401 from JWTMiddleware
// returns before any handler runs. The only evidence a successful login ever
// happened was a row appearing in refresh_tokens, which says nothing about the
// attempts that failed.
//
// This must be the OUTERMOST middleware, wrapping CORS rather than sitting
// inside it. CORS answers preflight OPTIONS itself and never calls through, so
// anything mounted underneath it cannot see a failing preflight — which is
// exactly the class of failure that is hardest to diagnose from the browser
// side.
//
// ── What is deliberately NOT logged ─────────────────────────────────────────
//
// Request bodies, the Authorization header, and query-string *values*. Bodies
// carry passwords on the login route; the header carries a bearer token that
// is valid for 15 minutes, and anyone reading the log could replay it. Query
// values carry member phone numbers on every search — real PII that would then
// live in a plaintext log file, be copied into any log aggregator, and outlive
// the member's deletion from the database.
//
// Query *keys* are kept, because "which filters were applied" is most of the
// diagnostic value and none of the risk.
func RequestLog() func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()

			// The identity holder is attached before the request goes down the
			// chain, so JWTMiddleware — which runs deeper — can fill it in and
			// have this outer frame observe the result. A plain context value
			// would not work: the deeper middleware creates a *derived* context
			// that this frame never sees.
			id := &identity{}
			r = r.WithContext(context.WithValue(r.Context(), identityKey{}, id))

			rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}

			// Deferred so a panic in a handler is still recorded. net/http
			// recovers panics per connection, and without this the request that
			// caused one would be the single request missing from the log.
			defer func() {
				log.Printf("%3d %-6s %s %s%s %s",
					rec.status,
					r.Method,
					r.URL.Path,
					queryKeys(r.URL.RawQuery),
					id.String(),
					duration(time.Since(start)),
				)
			}()

			next.ServeHTTP(rec, r)
		})
	}
}

// ── Identity, published by JWTMiddleware ────────────────────────────────────

type identityKey struct{}

type identity struct {
	gymID  int64
	userID int64
	role   string
}

func (i *identity) String() string {
	if i == nil || i.userID == 0 {
		return " anon"
	}
	return " gym=" + itoa(i.gymID) + " user=" + itoa(i.userID) + " " + i.role
}

// setIdentity records who a request turned out to belong to. Called by
// JWTMiddleware once the token has been verified — never before, so an
// unauthenticated or rejected request stays "anon" and cannot be attributed to
// whoever the caller merely *claimed* to be.
func setIdentity(ctx context.Context, gymID, userID int64, role string) {
	if id, ok := ctx.Value(identityKey{}).(*identity); ok {
		id.gymID, id.userID, id.role = gymID, userID, role
	}
}

// ── Response capture ────────────────────────────────────────────────────────

type statusRecorder struct {
	http.ResponseWriter
	status  int
	written bool
}

func (r *statusRecorder) WriteHeader(code int) {
	if !r.written {
		r.status = code
		r.written = true
	}
	r.ResponseWriter.WriteHeader(code)
}

func (r *statusRecorder) Write(b []byte) (int, error) {
	r.written = true // an implicit 200
	return r.ResponseWriter.Write(b)
}

// Flush keeps streaming responses working. A ResponseWriter wrapper that drops
// this silently breaks any handler relying on it.
func (r *statusRecorder) Flush() {
	if f, ok := r.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}

// ── Formatting helpers ──────────────────────────────────────────────────────

// queryKeys renders the parameter names present, without their values.
func queryKeys(raw string) string {
	if raw == "" {
		return ""
	}
	seen := make(map[string]struct{})
	for _, pair := range strings.Split(raw, "&") {
		k, _, _ := strings.Cut(pair, "=")
		if k = strings.TrimSpace(k); k != "" {
			seen[k] = struct{}{}
		}
	}
	if len(seen) == 0 {
		return ""
	}
	keys := make([]string, 0, len(seen))
	for k := range seen {
		keys = append(keys, k)
	}
	sort.Strings(keys) // stable output, so identical requests log identically
	return "?" + strings.Join(keys, ",")
}

func duration(d time.Duration) string {
	switch {
	case d >= time.Second:
		return d.Round(10 * time.Millisecond).String()
	case d >= time.Millisecond:
		return d.Round(100 * time.Microsecond).String()
	default:
		return d.Round(time.Microsecond).String()
	}
}

func itoa(n int64) string {
	if n == 0 {
		return "0"
	}
	var buf [20]byte
	i := len(buf)
	neg := n < 0
	if neg {
		n = -n
	}
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}

// clientIP is kept for the day this sits behind a proxy and the direct
// RemoteAddr stops being meaningful. Unused today by design: logging an IP per
// request is personal data under the DPDP Act, and there is no retention
// policy for these logs yet.
func clientIP(r *http.Request) string {
	if fwd := r.Header.Get("X-Forwarded-For"); fwd != "" {
		if first, _, found := strings.Cut(fwd, ","); found {
			return strings.TrimSpace(first)
		}
		return strings.TrimSpace(fwd)
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
