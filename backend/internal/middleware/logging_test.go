package middleware

import (
	"bytes"
	"log"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// capture swaps the standard logger's output for the duration of fn.
func capture(t *testing.T, fn func()) string {
	t.Helper()
	var buf bytes.Buffer
	old := log.Writer()
	flags := log.Flags()
	log.SetOutput(&buf)
	log.SetFlags(0)
	t.Cleanup(func() {
		log.SetOutput(old)
		log.SetFlags(flags)
	})
	fn()
	return buf.String()
}

func TestLogsStatusAndPath(t *testing.T) {
	h := RequestLog()(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusCreated)
	}))

	out := capture(t, func() {
		h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest("POST", "/api/v1/members", nil))
	})

	for _, want := range []string{"201", "POST", "/api/v1/members"} {
		if !strings.Contains(out, want) {
			t.Fatalf("log line missing %q: %s", want, out)
		}
	}
}

// A handler that never calls WriteHeader still returns 200 — the recorder must
// not report 0 for the most common response in the whole API.
func TestImplicitTwoHundredIsRecorded(t *testing.T) {
	h := RequestLog()(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"ok":true}`))
	}))

	out := capture(t, func() {
		h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest("GET", "/health", nil))
	})

	if !strings.Contains(out, "200") {
		t.Fatalf("expected an implicit 200: %s", out)
	}
}

// The reason this middleware exists: a rejected login must leave a trace.
func TestUnauthorizedRequestIsStillLogged(t *testing.T) {
	h := RequestLog()(JWTMiddleware("test-secret")(
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			t.Fatal("handler must not run for an unauthenticated request")
		})))

	out := capture(t, func() {
		h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest("GET", "/api/v1/members", nil))
	})

	if !strings.Contains(out, "401") {
		t.Fatalf("a rejected request left no 401 in the log: %s", out)
	}
	if !strings.Contains(out, "anon") {
		t.Fatalf("an unauthenticated request must log as anon: %s", out)
	}
}

func TestAuthenticatedRequestIsAttributedToItsGym(t *testing.T) {
	const secret = "test-secret"
	token, err := GenerateAccessToken(7, 3, "owner", secret)
	if err != nil {
		t.Fatalf("token: %v", err)
	}

	h := RequestLog()(JWTMiddleware(secret)(
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {})))

	req := httptest.NewRequest("GET", "/api/v1/members", nil)
	req.Header.Set("Authorization", "Bearer "+token)

	out := capture(t, func() { h.ServeHTTP(httptest.NewRecorder(), req) })

	// Tenant attribution is the point: with many gyms in one database, a log
	// line that cannot be traced to a gym cannot answer a support call.
	for _, want := range []string{"gym=3", "user=7", "owner"} {
		if !strings.Contains(out, want) {
			t.Fatalf("log line missing %q: %s", want, out)
		}
	}
}

// An invalid token must never be able to write its claimed gym id into the log.
func TestForgedTokenIsNotAttributed(t *testing.T) {
	forged, err := GenerateAccessToken(99, 42, "owner", "the-wrong-secret")
	if err != nil {
		t.Fatalf("token: %v", err)
	}

	h := RequestLog()(JWTMiddleware("the-real-secret")(
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			t.Fatal("handler must not run for a forged token")
		})))

	req := httptest.NewRequest("GET", "/api/v1/members", nil)
	req.Header.Set("Authorization", "Bearer "+forged)

	out := capture(t, func() { h.ServeHTTP(httptest.NewRecorder(), req) })

	if strings.Contains(out, "gym=42") || strings.Contains(out, "user=99") {
		t.Fatalf("forged claims reached the log: %s", out)
	}
	if !strings.Contains(out, "anon") {
		t.Fatalf("expected anon for a forged token: %s", out)
	}
}

// Query values carry member phone numbers on every search screen.
func TestQueryValuesAreNeverLogged(t *testing.T) {
	h := RequestLog()(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))

	out := capture(t, func() {
		h.ServeHTTP(httptest.NewRecorder(),
			httptest.NewRequest("GET", "/api/v1/members?search=9876543210&status=active", nil))
	})

	if strings.Contains(out, "9876543210") {
		t.Fatalf("a phone number reached the log: %s", out)
	}
	if !strings.Contains(out, "search") || !strings.Contains(out, "status") {
		t.Fatalf("query keys should be kept: %s", out)
	}
}

// The bearer token is replayable for 15 minutes; it must not sit in a log file.
func TestAuthorizationHeaderIsNeverLogged(t *testing.T) {
	const secret = "test-secret"
	token, _ := GenerateAccessToken(1, 1, "owner", secret)

	h := RequestLog()(JWTMiddleware(secret)(
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {})))

	req := httptest.NewRequest("GET", "/api/v1/members", nil)
	req.Header.Set("Authorization", "Bearer "+token)

	out := capture(t, func() { h.ServeHTTP(httptest.NewRecorder(), req) })

	if strings.Contains(out, token) {
		t.Fatalf("the access token was written to the log: %s", out)
	}
}

// A panicking handler is the one request you most need in the log.
func TestPanicIsStillLogged(t *testing.T) {
	h := RequestLog()(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		panic("boom")
	}))

	out := capture(t, func() {
		defer func() { _ = recover() }()
		h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest("GET", "/api/v1/members", nil))
	})

	if !strings.Contains(out, "/api/v1/members") {
		t.Fatalf("panicking request vanished from the log: %s", out)
	}
}

func TestQueryKeysAreDeduplicatedAndSorted(t *testing.T) {
	if got := queryKeys("b=1&a=2&b=3"); got != "?a,b" {
		t.Fatalf("queryKeys = %q, want ?a,b", got)
	}
	if got := queryKeys(""); got != "" {
		t.Fatalf("empty query should render nothing, got %q", got)
	}
}

func TestItoa(t *testing.T) {
	for _, c := range []struct {
		in   int64
		want string
	}{{0, "0"}, {7, "7"}, {1234, "1234"}, {-42, "-42"}} {
		if got := itoa(c.in); got != c.want {
			t.Fatalf("itoa(%d) = %q, want %q", c.in, got, c.want)
		}
	}
}
