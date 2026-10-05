package entitlements

import (
	"context"
	"fmt"
	"log"
	"net/http"

	"gymcrm/internal/database"
	"gymcrm/internal/shared/response"
)

// TierProvider looks up a gym's current plan tier. Implemented by
// *gyms.Repository (see internal/gyms/repository.go's GetPlanTier) — this
// package deliberately doesn't import gyms itself, so a small interface is
// how it stays decoupled from that package's concrete types.
//
// A DB lookup per gated request, not something baked into the JWT: an
// owner who upgrades or downgrades a plan should take effect on their next
// click, not their next login.
type TierProvider interface {
	GetPlanTier(ctx context.Context, gymID int64) (string, error)
}

// RequireFeature builds a middleware that blocks a route unless the
// caller's gym is on a tier that includes feature. Must be chained AFTER
// JWTMiddleware, same rule as middleware.OwnerOnly — it reads the tenant
// context JWTMiddleware populates.
//
// A Feature missing from minTier is a programming error (a typo in the
// catalog, or a route wired to a Feature nobody registered), not a runtime
// condition to degrade gracefully from — it panics at wiring time
// (main.go's route table is built once at startup), the same "fail loud,
// fail early" reasoning as database.MustGetTenant.
func RequireFeature(provider TierProvider, feature Feature) func(http.Handler) http.Handler {
	floor, ok := minTier[feature]
	if !ok {
		panic(fmt.Sprintf("entitlements: RequireFeature(%q): no tier registered for this feature", feature))
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			tc := database.MustGetTenant(r.Context()) // safe: JWTMiddleware ran first

			raw, err := provider.GetPlanTier(r.Context(), tc.GymID())
			if err != nil {
				log.Printf("entitlements: GetPlanTier(gym=%d): %v", tc.GymID(), err)
				response.InternalServerError(w)
				return
			}
			tier, err := ParseTier(raw)
			if err != nil {
				log.Printf("entitlements: %v", err)
				response.InternalServerError(w)
				return
			}
			if !tier.atLeast(floor) {
				response.Forbidden(w, fmt.Sprintf("this feature needs the %s plan or higher", floor))
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
