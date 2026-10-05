package gyms

import (
	"context"

	"gorm.io/gorm"
)

// Repository handles the gyms table's public-advertisement-profile reads.
//
// Deliberately NOT tenant-scoped: every other repository in this codebase
// starts from database.ScopedDB(ctx, db) because a request always carries
// one gym's own JWT. GetPublicProfile has no such context — it's reached by
// an anonymous visitor or a search-engine crawler that was never signed
// in — so it queries r.db directly and relies on the WHERE clause itself
// (public_slug + published = true) to be the only access control there is.
type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository {
	return &Repository{db: db}
}

// GetByID fetches a gym by its own id — used by the owner-facing settings
// read/write path, unlike GetPublicProfile which is slug-and-published only.
func (r *Repository) GetByID(ctx context.Context, gymID int64) (*Gym, error) {
	var gym Gym
	err := r.db.WithContext(ctx).Where("id = ?", gymID).First(&gym).Error
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, nil
		}
		return nil, err
	}
	return &gym, nil
}

// GetPlanTier returns gymID's raw plan_tier column — this is what makes
// *Repository satisfy internal/entitlements.TierProvider (see
// middleware.go's comment there for why that's a small interface rather
// than entitlements importing this package directly).
func (r *Repository) GetPlanTier(ctx context.Context, gymID int64) (string, error) {
	var tier string
	err := r.db.WithContext(ctx).
		Table("gyms").
		Where("id = ?", gymID).
		Select("plan_tier").
		Scan(&tier).Error
	if err != nil {
		return "", err
	}
	if tier == "" {
		return "", gorm.ErrRecordNotFound
	}
	return tier, nil
}

// SlugTaken reports whether slug is already in use by a gym other than
// excludeGymID — checked across every gym, not scoped to one tenant, since
// public_slug is the shared namespace every gym's page URL is drawn from.
func (r *Repository) SlugTaken(ctx context.Context, slug string, excludeGymID int64) (bool, error) {
	var count int64
	err := r.db.WithContext(ctx).
		Table("gyms").
		Where("public_slug = ? AND id != ?", slug, excludeGymID).
		Count(&count).Error
	if err != nil {
		return false, err
	}
	return count > 0, nil
}

// UpdatePublicProfile applies a partial set of column updates to gymID's own
// row. fields is built by the service layer from whichever request fields
// were actually sent — same "only touch what was provided" contract as
// branches.Repository's SetTargets.
func (r *Repository) UpdatePublicProfile(ctx context.Context, gymID int64, fields map[string]interface{}) error {
	if len(fields) == 0 {
		return nil
	}
	return r.db.WithContext(ctx).Table("gyms").Where("id = ?", gymID).Updates(fields).Error
}

// GetPublicProfile fetches the gym at slug, but only if it has published its
// page — an unpublished or nonexistent slug both return (nil, nil), the
// same "not found" either way, so a crawler or a curious visitor learns
// nothing about which slugs exist but aren't public yet.
func (r *Repository) GetPublicProfile(ctx context.Context, slug string) (*Gym, error) {
	var gym Gym
	err := r.db.WithContext(ctx).
		Where("public_slug = ? AND published = TRUE", slug).
		First(&gym).Error
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, nil
		}
		return nil, err
	}
	return &gym, nil
}
