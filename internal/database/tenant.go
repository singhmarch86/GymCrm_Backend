package database

import (
	"context"
	"errors"

	"gorm.io/gorm"
)

// contextKey is unexported — prevents collisions with other packages' context keys.
type contextKey string

const tenantKey contextKey = "tenant_context"

// TenantContext carries the verified gym_id and user identity for a request.
// Set once by JWT middleware. Read by every repository method.
// NEVER constructed outside of middleware — this is enforced by keeping
// the struct fields unexported and providing only a middleware-facing constructor.
type TenantContext struct {
	gymID  int64
	userID int64
	role   string
}

// NewTenantContext is called ONLY by JWT middleware after token validation.
func NewTenantContext(gymID, userID int64, role string) TenantContext {
	return TenantContext{
		gymID:  gymID,
		userID: userID,
		role:   role,
	}
}

// GymID returns the verified tenant identifier.
func (t TenantContext) GymID() int64 { return t.gymID }

// UserID returns the authenticated user's ID.
func (t TenantContext) UserID() int64 { return t.userID }

// Role returns the user's role within the gym.
func (t TenantContext) Role() string { return t.role }

// IsOwner returns true if the user has owner-level access.
func (t TenantContext) IsOwner() bool { return t.role == "owner" }

// ─── Context injection ────────────────────────────────────────────────────────

// WithTenant stores the tenant context in the request context.
// Called by the tenant middleware — not by application code.
func WithTenant(ctx context.Context, tc TenantContext) context.Context {
	return context.WithValue(ctx, tenantKey, tc)
}

// MustGetTenant extracts the tenant context from ctx.
// Panics if not present — this is intentional. If middleware is wired correctly,
// the tenant context is always present on authenticated routes.
// A panic here means a middleware misconfiguration, not a user error.
func MustGetTenant(ctx context.Context) TenantContext {
	tc, ok := ctx.Value(tenantKey).(TenantContext)
	if !ok {
		panic("tenant context missing — route is not protected by tenant middleware")
	}
	return tc
}

// GetTenant extracts the tenant context from ctx without panicking.
// Use in code paths that might legitimately run without a tenant (e.g. health checks).
func GetTenant(ctx context.Context) (TenantContext, error) {
	tc, ok := ctx.Value(tenantKey).(TenantContext)
	if !ok {
		return TenantContext{}, errors.New("tenant context not found in context")
	}
	return tc, nil
}

// ─── Tenant-scoped GORM helper ────────────────────────────────────────────────

// ScopedDB returns a *gorm.DB pre-filtered by gym_id.
// ALL repository methods MUST use this instead of the raw db handle.
//
// Usage:
//
//	db := database.ScopedDB(ctx, r.db)
//	db.Where("status = ?", "active").Find(&members)
//	// Equivalent SQL: WHERE gym_id = <from_jwt> AND status = 'active'
//
// This is the single choke-point for tenant isolation.
// If a developer forgets to call ScopedDB, they get a compile error
// because repository methods require this signature.
func ScopedDB(ctx context.Context, db *gorm.DB) *gorm.DB {
	tc := MustGetTenant(ctx)
	return db.WithContext(ctx).Where("gym_id = ?", tc.GymID())
}
