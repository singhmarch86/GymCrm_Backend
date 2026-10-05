package middleware

import (
	"net/http"
	"strings"
)

// CORS returns middleware that emits cross-origin headers and answers
// preflight requests.
//
// Only browser clients need this. Native clients (the Flutter macOS/iOS/Android
// builds) are not subject to the same-origin policy and are unaffected either
// way — but a Flutter *web* build served from a different port than the API
// cannot call it at all without these headers: the browser sends a preflight
// OPTIONS first (any request carrying Content-Type: application/json is
// non-"simple"), and without a 2xx + Access-Control-Allow-Origin reply it
// blocks the real request before it is ever sent.
//
// allowedOrigins lists the exact origins to permit, e.g.
// "http://localhost:8091". The single entry "*" permits any origin — fine for
// local development, never for production. An empty slice disables CORS
// entirely (no headers emitted, preflights fall through to the router's 405),
// which is the correct default for a native-only deployment.
func CORS(allowedOrigins []string) func(http.Handler) http.Handler {
	allowAll := len(allowedOrigins) == 1 && strings.TrimSpace(allowedOrigins[0]) == "*"

	allowed := make(map[string]struct{}, len(allowedOrigins))
	for _, o := range allowedOrigins {
		if trimmed := strings.TrimSpace(o); trimmed != "" {
			allowed[strings.ToLower(trimmed)] = struct{}{}
		}
	}

	enabled := allowAll || len(allowed) > 0

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			origin := r.Header.Get("Origin")

			// Not a cross-origin browser request (or CORS is off) — nothing to add.
			if !enabled || origin == "" {
				next.ServeHTTP(w, r)
				return
			}

			_, originAllowed := allowed[strings.ToLower(origin)]
			if allowAll || originAllowed {
				// Echo the caller's origin rather than "*" so the same response
				// stays valid if credentialed requests are ever added. Vary is
				// required whenever the header depends on the request, or a
				// shared cache may hand one origin's response to another.
				w.Header().Set("Access-Control-Allow-Origin", origin)
				w.Header().Add("Vary", "Origin")
			}

			// Preflight — answer it here instead of letting it reach the router,
			// which registers only method-qualified routes (no OPTIONS) and would
			// return 405, which the browser treats as a failed preflight.
			if r.Method == http.MethodOptions {
				w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
				w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
				w.Header().Set("Access-Control-Max-Age", "300")
				w.Header().Add("Vary", "Access-Control-Request-Method")
				w.Header().Add("Vary", "Access-Control-Request-Headers")
				w.WriteHeader(http.StatusNoContent)
				return
			}

			next.ServeHTTP(w, r)
		})
	}
}
