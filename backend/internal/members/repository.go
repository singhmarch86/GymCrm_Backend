package members

import (
	"context"
	"errors"
	"strings"
	"time"

	"gorm.io/gorm"

	"gymcrm/internal/database"
	"gymcrm/internal/shared/pagination"
)

// Repository handles all member DB operations.
//
// TENANT ISOLATION RULES — enforced here, not in the service:
//  1. Every query MUST start with database.ScopedDB(ctx, r.db)
//  2. ScopedDB injects WHERE gym_id = <from_jwt> automatically
//  3. No raw r.db calls anywhere in this file
//  4. Member IDs are never trusted alone — always paired with gym_id
//
// This means: even if a bug in the service passes the wrong member ID,
// the WHERE gym_id clause prevents cross-gym data access.
type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository {
	return &Repository{db: db}
}

// ─── Create ───────────────────────────────────────────────────────────────────

func (r *Repository) Create(ctx context.Context, member *Member) error {
	return database.ScopedDB(ctx, r.db).Create(member).Error
}

// ─── Read ─────────────────────────────────────────────────────────────────────

// FindByID fetches a single member scoped to the tenant gym.
// Returns nil, nil if not found — caller decides if that's an error.
// NEVER use FindByID without gym_id scope — ScopedDB enforces this.
func (r *Repository) FindByID(ctx context.Context, id int64) (*Member, error) {
	var member Member
	err := database.ScopedDB(ctx, r.db).
		Where("id = ?", id).
		First(&member).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &member, err
}

// List returns a paginated, filtered list of members for the tenant gym.
// Supports filtering by status and searching by first_name, last_name, phone.
//
// Query pattern: WHERE gym_id = ? [AND status = ?] [AND (first_name ILIKE ? OR ...)]
// Index used: idx_members_gym_status (gym_id, status) or idx_members_gym_firstname
func (r *Repository) List(ctx context.Context, params ListMembersRequest) ([]Member, int64, error) {
	p := pagination.Params{
		Page:    params.Page,
		PerPage: params.PerPage,
		Offset:  (params.Page - 1) * params.PerPage,
	}

	q := database.ScopedDB(ctx, r.db).Model(&Member{})

	if params.Status != "" {
		q = q.Where("status = ?", params.Status)
	}

	if params.Search != "" {
		// ILIKE for case-insensitive search — Postgres specific, intentional.
		// In V2: replace with pg_trgm GIN index for full-text search.
		term := "%" + strings.TrimSpace(params.Search) + "%"
		q = q.Where(
			"first_name ILIKE ? OR last_name ILIKE ? OR phone LIKE ?",
			term, term, term,
		)
	}

	// Count total before applying pagination (same filters, no LIMIT)
	var total int64
	if err := q.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var members []Member
	err := q.
		Order("created_at DESC").
		Limit(p.PerPage).
		Offset(p.Offset).
		Find(&members).Error

	return members, total, err
}

// Search is a dedicated search endpoint (GET /members/search?q=).
// Separated from List so it can have different pagination defaults
// and be optimised independently in V2.
func (r *Repository) Search(ctx context.Context, query string, p pagination.Params) ([]Member, int64, error) {
	term := "%" + strings.TrimSpace(query) + "%"

	q := database.ScopedDB(ctx, r.db).Model(&Member{}).
		Where(
			"first_name ILIKE ? OR last_name ILIKE ? OR phone LIKE ?",
			term, term, term,
		)

	var total int64
	if err := q.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var members []Member
	err := q.
		Order("first_name ASC, last_name ASC").
		Limit(p.PerPage).
		Offset(p.Offset).
		Find(&members).Error

	return members, total, err
}

// FindExpiring returns members whose expiry_date falls within the next N days.
// Core query for the retention dashboard.
//
// Index used: idx_members_gym_expiry (gym_id, expiry_date)
func (r *Repository) FindExpiring(ctx context.Context, days int, p pagination.Params) ([]Member, int64, error) {
	now := time.Now()
	cutoff := now.AddDate(0, 0, days)

	q := database.ScopedDB(ctx, r.db).Model(&Member{}).
		Where("expiry_date BETWEEN ? AND ?", now, cutoff).
		Where("status = ?", MemberStatusActive)

	var total int64
	if err := q.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var members []Member
	err := q.
		Order("expiry_date ASC"). // soonest expiry first
		Limit(p.PerPage).
		Offset(p.Offset).
		Find(&members).Error

	return members, total, err
}

// ─── Update ───────────────────────────────────────────────────────────────────

// Update applies a map of changes to a member.
// Uses map[string]interface{} so GORM updates zero-value fields correctly.
// ScopedDB ensures the update can only touch this gym's members.
func (r *Repository) Update(ctx context.Context, id int64, updates map[string]interface{}) error {
	result := database.ScopedDB(ctx, r.db).
		Model(&Member{}).
		Where("id = ?", id).
		Updates(updates)

	if result.Error != nil {
		return result.Error
	}
	// RowsAffected = 0 means the member wasn't found in THIS gym
	// (could exist in another gym — we'll never know, by design)
	if result.RowsAffected == 0 {
		return gorm.ErrRecordNotFound
	}
	return nil
}

// ─── Delete ───────────────────────────────────────────────────────────────────

// SoftDelete sets deleted_at on the member record.
// GORM's soft delete automatically excludes deleted records from all queries.
// The record remains in the DB for audit — never hard deleted.
func (r *Repository) SoftDelete(ctx context.Context, id int64) error {
	result := database.ScopedDB(ctx, r.db).
		Where("id = ?", id).
		Delete(&Member{})

	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return gorm.ErrRecordNotFound
	}
	return nil
}

// ─── Renewals view ────────────────────────────────────────────────────────────

// MemberRenewalRow is the flat join result for the "members due for renewal" view.
// Joins members + membership_plans. LEFT JOIN — members with no plan assigned
// are still included (PlanName/PlanID will be nil).
type MemberRenewalRow struct {
	ID         int64
	FirstName  string
	LastName   string
	Phone      string
	ExpiryDate *time.Time
	Status     string
	PlanID     *int64
	PlanName   *string
}

// FindDueForRenewal returns members relevant to the renewals screen: anyone
// with an expiry_date set, sorted soonest-first. Status filtering (today,
// tomorrow, this week, expired) and search are applied by the service layer
// in Go, since the bucketing logic depends on "now" at request time, not
// storage time, and keeping it in Go avoids fragile timezone-sensitive SQL.
//
// gym_id is qualified as "members.gym_id" rather than using ScopedDB directly —
// membership_plans also has a gym_id column, so an unqualified WHERE gym_id = ?
// after a JOIN raises "column reference gym_id is ambiguous" in Postgres.
// Same fix as renewals/repository.go's scopedRenewalsDB pattern.
//
// Index used: idx_members_gym_expiry (gym_id, expiry_date)
func (r *Repository) FindDueForRenewal(ctx context.Context) ([]MemberRenewalRow, error) {
	tc := database.MustGetTenant(ctx)
	var rows []MemberRenewalRow

	err := r.db.WithContext(ctx).
		Table("members").
		Select(`members.id, members.first_name, members.last_name, members.phone,
			members.expiry_date, members.status,
			membership_plans.id   AS plan_id,
			membership_plans.name AS plan_name`).
		Joins("LEFT JOIN membership_plans ON membership_plans.id = members.membership_plan_id").
		Where("members.gym_id = ?", tc.GymID()).
		Where("members.expiry_date IS NOT NULL").
		Where("members.deleted_at IS NULL").
		Order("members.expiry_date ASC").
		Scan(&rows).Error

	return rows, err
}

// FindPlanNameByID resolves a single plan's name, scoped to the tenant gym.
// Used to enrich MemberResponse with membership_plan_name without requiring
// the members package to import the plans package.
func (r *Repository) FindPlanNameByID(ctx context.Context, planID int64) (string, error) {
	var name string
	err := database.ScopedDB(ctx, r.db).
		Table("membership_plans").
		Select("name").
		Where("id = ? AND deleted_at IS NULL", planID).
		Scan(&name).Error
	return name, err
}

// ─── Uniqueness checks ────────────────────────────────────────────────────────

// PhoneExistsInGym checks if a phone number is already used by another member
// in the same gym. Excludes the given memberID (for update checks).
// excludeID = 0 means no exclusion (create flow).
func (r *Repository) PhoneExistsInGym(ctx context.Context, phone string, excludeID int64) (bool, error) {
	q := database.ScopedDB(ctx, r.db).Model(&Member{}).
		Where("phone = ?", phone)

	if excludeID > 0 {
		q = q.Where("id != ?", excludeID)
	}

	var count int64
	err := q.Count(&count).Error
	return count > 0, err
}
