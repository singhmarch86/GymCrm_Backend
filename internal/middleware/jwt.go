package middleware

import (
	"net/http"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"

	"gymcrm/internal/database"
	"gymcrm/internal/shared/response"
)

// Claims is the JWT payload. gym_id is embedded — every request carries its tenant.
type Claims struct {
	UserID int64  `json:"user_id"`
	GymID  int64  `json:"gym_id"`
	Role   string `json:"role"`
	jwt.RegisteredClaims
}

// JWTMiddleware validates the Bearer token and injects TenantContext into the request.
// All routes that need authentication MUST use this middleware.
// Routes beyond this middleware are guaranteed to have a valid tenant context.
func JWTMiddleware(jwtSecret string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			tokenStr, err := extractBearerToken(r)
			if err != nil {
				response.Unauthorized(w, "missing or malformed authorization header")
				return
			}

			claims, err := parseAndValidate(tokenStr, jwtSecret)
			if err != nil {
				response.Unauthorized(w, "invalid or expired token")
				return
			}

			// Inject tenant context — from this point, all downstream code
			// can call database.MustGetTenant(ctx) safely.
			tc := database.NewTenantContext(claims.GymID, claims.UserID, claims.Role)
			ctx := database.WithTenant(r.Context(), tc)

			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// OwnerOnly is a middleware that restricts an endpoint to gym owners.
// Must be chained AFTER JWTMiddleware.
func OwnerOnly(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		tc := database.MustGetTenant(r.Context()) // safe: JWTMiddleware ran first
		if !tc.IsOwner() {
			response.Forbidden(w, "owner access required")
			return
		}
		next.ServeHTTP(w, r)
	})
}

// ─── Token generation (used by auth service) ──────────────────────────────────

// AccessTokenTTL — short-lived, rotated frequently.
const AccessTokenTTL = 15 * time.Minute

// RefreshTokenTTL — long-lived, stored in DB, revocable.
const RefreshTokenTTL = 30 * 24 * time.Hour

// GenerateAccessToken creates a signed JWT access token.
func GenerateAccessToken(userID, gymID int64, role, secret string) (string, error) {
	claims := Claims{
		UserID: userID,
		GymID:  gymID,
		Role:   role,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(AccessTokenTTL)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Issuer:    "gymcrm",
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(secret))
}

// ─── Private helpers ──────────────────────────────────────────────────────────

func extractBearerToken(r *http.Request) (string, error) {
	header := r.Header.Get("Authorization")
	if header == "" {
		return "", errMissingHeader
	}
	parts := strings.SplitN(header, " ", 2)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "bearer") {
		return "", errMalformedHeader
	}
	return parts[1], nil
}

func parseAndValidate(tokenStr, secret string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(
		tokenStr,
		&Claims{},
		func(t *jwt.Token) (interface{}, error) {
			if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, errUnexpectedSigningMethod
			}
			return []byte(secret), nil
		},
		jwt.WithValidMethods([]string{"HS256"}),
		jwt.WithExpirationRequired(),
	)
	if err != nil {
		return nil, err
	}
	claims, ok := token.Claims.(*Claims)
	if !ok || claims.GymID == 0 || claims.UserID == 0 {
		return nil, errInvalidClaims
	}
	return claims, nil
}

// Sentinel errors — not exposed to HTTP responses (we return generic messages)
var (
	errMissingHeader           = http.ErrNoCookie // reuse stdlib sentinel
	errMalformedHeader         = &middlewareError{"malformed authorization header"}
	errUnexpectedSigningMethod = &middlewareError{"unexpected signing method"}
	errInvalidClaims           = &middlewareError{"invalid token claims"}
)

type middlewareError struct{ msg string }

func (e *middlewareError) Error() string { return e.msg }
