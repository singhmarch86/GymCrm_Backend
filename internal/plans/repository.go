package plans

import (
	"context"
	"errors"
	"strings"

	"gorm.io/gorm"

	"gymcrm/internal/database"
	"gymcrm/internal/shared/pagination"
)

// Repository handles all membership_plans DB operations.
//
// TENANT ISOLATION — same rules as members:
//   1. Every query starts with database.ScopedDB(ctx, r.db)
//   2. gym_id comes from context, never from parameters
//   3. Plan IDs are always paired with gym_id scope
//   4. Zero raw r.db calls in this file
type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository {
	return &Repository{db: db}
}

// ─── Create ───────────────────────────────────────────────────────────────────

func (r *Repository) Create(ctx context.Context, plan *MembershipPlan) error {
	return database.ScopedDB(ctx, r.db).Create(plan).Error
}

// ─── Read ─────────────────────────────────────────────────────────────────────

// FindByID fetches a single plan scoped to the tenant gym.
// Returns nil, nil when not found — caller decides if that's an error.
func (r *Repository) FindByID(ctx context.Context, id int64) (*MembershipPlan, error) {
	var plan MembershipPlan
	err := database.ScopedDB(ctx, r.db).
		Where("id = ?", id).
		First(&plan).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &plan, err
}

// List returns a paginated, optionally filtered list of plans for the tenant gym.
// search matches plan name (case-insensitive).
// isActive nil = all plans, true = active only, false = inactive only.
func (r *Repository) List(ctx context.Context, req ListPlansRequest) ([]MembershipPlan, int64, error) {
	p := pagination.Params{
		Page:    req.Page,
		PerPage: req.PerPage,
		Offset:  (req.Page - 1) * req.PerPage,
	}

	q := database.ScopedDB(ctx, r.db).Model(&MembershipPlan{})

	if req.IsActive != nil {
		q = q.Where("is_active = ?", *req.IsActive)
	}

	if req.Search != "" {
		// ILIKE on name — case-insensitive, consistent with the LOWER() index
		term := "%" + strings.TrimSpace(req.Search) + "%"
		q = q.Where("name ILIKE ?", term)
	}

	var total int64
	if err := q.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var plans []MembershipPlan
	err := q.
		Order("is_active DESC, name ASC"). // active plans first, then alphabetical
		Limit(p.PerPage).
		Offset(p.Offset).
		Find(&plans).Error

	return plans, total, err
}

// FindActive returns all active, non-deleted plans for the tenant gym.
// Used by the /plans/active endpoint and by the members module when
// assigning a plan to a member.
func (r *Repository) FindActive(ctx context.Context, p pagination.Params) ([]MembershipPlan, int64, error) {
	q := database.ScopedDB(ctx, r.db).Model(&MembershipPlan{}).
		Where("is_active = ?", true)

	var total int64
	if err := q.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var plans []MembershipPlan
	err := q.
		Order("name ASC").
		Limit(p.PerPage).
		Offset(p.Offset).
		Find(&plans).Error

	return plans, total, err
}

// ─── Update ───────────────────────────────────────────────────────────────────

// Update applies a map of changes to a plan within the tenant gym.
// RowsAffected = 0 means the plan wasn't found in this gym.
func (r *Repository) Update(ctx context.Context, id int64, updates map[string]interface{}) error {
	result := database.ScopedDB(ctx, r.db).
		Model(&MembershipPlan{}).
		Where("id = ?", id).
		Updates(updates)
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return gorm.ErrRecordNotFound
	}
	return nil
}

// ─── Delete ───────────────────────────────────────────────────────────────────

// SoftDelete sets deleted_at — plan disappears from all queries.
// Existing member.membership_plan_id references remain valid (FK still exists).
// Existing renewal.plan_id references remain valid.
func (r *Repository) SoftDelete(ctx context.Context, id int64) error {
	result := database.ScopedDB(ctx, r.db).
		Where("id = ?", id).
		Delete(&MembershipPlan{})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return gorm.ErrRecordNotFound
	}
	return nil
}

// ─── Uniqueness + validation helpers ─────────────────────────────────────────

// NameExistsInGym checks case-insensitive name uniqueness within the tenant gym.
// excludeID = 0 for create, excludeID = planID for update.
// Mirrors the DB index: UNIQUE (gym_id, LOWER(name)) WHERE deleted_at IS NULL.
func (r *Repository) NameExistsInGym(ctx context.Context, name string, excludeID int64) (bool, error) {
	q := database.ScopedDB(ctx, r.db).Model(&MembershipPlan{}).
		Where("LOWER(name) = LOWER(?)", name)

	if excludeID > 0 {
		q = q.Where("id != ?", excludeID)
	}

	var count int64
	err := q.Count(&count).Error
	return count > 0, err
}

// IsAssignable checks if a plan is active and belongs to the tenant gym.
// Called by the members service before assigning a plan to a member.
// Called by the renewals service before creating a renewal.
func (r *Repository) IsAssignable(ctx context.Context, planID int64) (bool, error) {
	var count int64
	err := database.ScopedDB(ctx, r.db).Model(&MembershipPlan{}).
		Where("id = ? AND is_active = ?", planID, true).
		Count(&count).Error
	return count > 0, err
}

// CountMembersUsingPlan returns the number of non-deleted members currently
// assigned to this plan within the tenant gym.
// Used by dashboards and plan lifecycle management.
// NOTE: this query crosses into the members table — gym_id scoping is applied
// to both sides via the JOIN condition, not just the plans table.
func (r *Repository) CountMembersUsingPlan(ctx context.Context, planID int64) (int64, error) {
	tc := database.MustGetTenant(ctx)
	var count int64
	err := r.db.WithContext(ctx).
		Table("members").
		Where("membership_plan_id = ? AND gym_id = ? AND deleted_at IS NULL", planID, tc.GymID()).
		Count(&count).Error
	return count, err
}
