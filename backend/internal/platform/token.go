package platform

import (
	"crypto/hmac"
	"crypto/sha256"
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Platform tokens are a different kind from gym tokens (FR-12 §3): signed with
// a key derived from — but not equal to — the gym secret, carrying no gym_id.
// The gym middleware therefore fails their signature check outright, and
// nothing here accepts a gym token either.
const (
	ScopeSession = "session" // full console access, after password + TOTP
	ScopeEnroll  = "enroll"  // may only complete 2FA enrolment

	SessionTTL = 2 * time.Hour
	EnrollTTL  = 15 * time.Minute
)

type claims struct {
	AdminID int64  `json:"admin_id"`
	Scope   string `json:"scope"`
	jwt.RegisteredClaims
}

func signingKey(secret string) []byte {
	m := hmac.New(sha256.New, []byte(secret))
	m.Write([]byte("gymcrm-platform-token-v1"))
	return m.Sum(nil)
}

func issue(secret string, adminID int64, scope string, ttl time.Duration) (string, time.Time, error) {
	exp := time.Now().Add(ttl)
	c := claims{AdminID: adminID, Scope: scope, RegisteredClaims: jwt.RegisteredClaims{
		ExpiresAt: jwt.NewNumericDate(exp),
		IssuedAt:  jwt.NewNumericDate(time.Now()),
		Issuer:    "gymcrm-platform",
	}}
	s, err := jwt.NewWithClaims(jwt.SigningMethodHS256, c).SignedString(signingKey(secret))
	return s, exp, err
}

func parse(secret, tok string) (*claims, error) {
	c := &claims{}
	t, err := jwt.ParseWithClaims(tok, c, func(*jwt.Token) (interface{}, error) { return signingKey(secret), nil },
		jwt.WithValidMethods([]string{"HS256"}), jwt.WithExpirationRequired(), jwt.WithIssuer("gymcrm-platform"))
	if err != nil || !t.Valid || c.AdminID == 0 {
		return nil, errors.New("invalid platform token")
	}
	return c, nil
}
