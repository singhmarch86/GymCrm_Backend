package renewals

import (
	"context"
	"errors"
	"time"

	"gorm.io/gorm"

	"gymcrm/internal/database"
	"gymcrm/internal/shared/pagination"
)

// Repository handles all renewals DB operations.
//
// TENANT ISOLATION:
//   1. Every query starts with database.ScopedDB(ctx, r.db)
//   2. Joined queries qualify gym_id as "renewals.gym_id" to avoid ambiguity
//   3. No Update or Delete methods — renewals are append-only
type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository {
	return &Repository{db: db}
}

// scopedRenewalsDB returns a scoped DB with gym_id explicitly qualified.
// Used for all queries that JOIN other tables which also have gym_id.
// Without qualification, Postgres returns "column reference gym_id is ambiguous".
func (r *Repository) scopedRenewalsDB(ctx context.Context) *gorm.DB {
	tc := database.MustGetTenant(ctx)
	return r.db.WithContext(ctx).Where("renewals.gym_id = ?", tc.GymID())
}

// ─── Create ───────────────────────────────────────────────────────────────────

func (r *Repository) Create(ctx context.Context, renewal *Renewal) error {
	return database.ScopedDB(ctx, r.db).Create(renewal).Error
}

// ─── Read — single ────────────────────────────────────────────────────────────

func (r *Repository) FindByID(ctx context.Context, id int64) (*RenewalWithContext, error) {
	var result RenewalWithContext
	err := r.scopedRenewalsDB(ctx).
		Table("renewals").
		Select(`renewals.*,
			members.first_name         AS member_first_name,
			members.last_name          AS member_last_name,
			membership_plans.name          AS plan_name,
			membership_plans.duration_days AS plan_duration_days`).
		Joins("JOIN members ON members.id = renewals.member_id").
		Joins("JOIN membership_plans ON membership_plans.id = renewals.plan_id").
		Where("renewals.id = ?", id).
		First(&result).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &result, err
}

// ─── Read — list ──────────────────────────────────────────────────────────────

func (r *Repository) List(ctx context.Context, req ListRenewalsRequest) ([]RenewalWithContext, int64, error) {
	p := pagination.Params{
		Page:    req.Page,
		PerPage: req.PerPage,
		Offset:  (req.Page - 1) * req.PerPage,
	}

	q := r.scopedRenewalsDB(ctx).
		Table("renewals").
		Select(`renewals.*,
			members.first_name         AS member_first_name,
			members.last_name          AS member_last_name,
			membership_plans.name          AS plan_name,
			membership_plans.duration_days AS plan_duration_days`).
		Joins("JOIN members ON members.id = renewals.member_id").
		Joins("JOIN membership_plans ON membership_plans.id = renewals.plan_id")

	if req.MemberID != nil {
		q = q.Where("renewals.member_id = ?", *req.MemberID)
	}
	if req.PlanID != nil {
		q = q.Where("renewals.plan_id = ?", *req.PlanID)
	}
	if req.DateFrom != nil {
		q = q.Where("renewals.renewal_date >= ?", *req.DateFrom)
	}
	if req.DateTo != nil {
		q = q.Where("renewals.renewal_date <= ?", *req.DateTo)
	}

	var total int64
	if err := q.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var results []RenewalWithContext
	err := q.
		Order("renewals.renewal_date DESC, renewals.id DESC").
		Limit(p.PerPage).
		Offset(p.Offset).
		Scan(&results).Error

	return results, total, err
}

func (r *Repository) FindByMember(ctx context.Context, memberID int64, p pagination.Params) ([]RenewalWithContext, int64, error) {
	q := r.scopedRenewalsDB(ctx).
		Table("renewals").
		Select(`renewals.*,
			members.first_name         AS member_first_name,
			members.last_name          AS member_last_name,
			membership_plans.name          AS plan_name,
			membership_plans.duration_days AS plan_duration_days`).
		Joins("JOIN members ON members.id = renewals.member_id").
		Joins("JOIN membership_plans ON membership_plans.id = renewals.plan_id").
		Where("renewals.member_id = ?", memberID)

	var total int64
	if err := q.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var results []RenewalWithContext
	err := q.
		Order("renewals.renewal_date DESC").
		Limit(p.PerPage).
		Offset(p.Offset).
		Scan(&results).Error

	return results, total, err
}

func (r *Repository) FindRecent(ctx context.Context, limit int) ([]RenewalWithContext, error) {
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	var results []RenewalWithContext
	err := r.scopedRenewalsDB(ctx).
		Table("renewals").
		Select(`renewals.*,
			members.first_name         AS member_first_name,
			members.last_name          AS member_last_name,
			membership_plans.name          AS plan_name,
			membership_plans.duration_days AS plan_duration_days`).
		Joins("JOIN members ON members.id = renewals.member_id").
		Joins("JOIN membership_plans ON membership_plans.id = renewals.plan_id").
		Order("renewals.renewal_date DESC, renewals.id DESC").
		Limit(limit).
		Scan(&results).Error
	return results, err
}

// ─── Cross-module helpers ─────────────────────────────────────────────────────

func (r *Repository) UpdateMemberExpiry(ctx context.Context, memberID int64, newExpiry time.Time) error {
	tc := database.MustGetTenant(ctx)
	return r.db.WithContext(ctx).
		Table("members").
		Where("id = ? AND gym_id = ?", memberID, tc.GymID()).
		Updates(map[string]interface{}{
			"expiry_date": newExpiry,
			"status":      "active",
		}).Error
}

type MemberSummary struct {
	ID         int64
	GymID      int64
	ExpiryDate *time.Time
	Status     string
}

func (r *Repository) FindMemberForRenewal(ctx context.Context, memberID int64) (*MemberSummary, error) {
	var m MemberSummary
	err := database.ScopedDB(ctx, r.db).
		Table("members").
		Select("id, gym_id, expiry_date, status").
		Where("id = ? AND deleted_at IS NULL", memberID).
		First(&m).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &m, err
}

type PlanSummary struct {
	ID           int64
	GymID        int64
	DurationDays int
	IsActive     bool
}

func (r *Repository) FindPlanForRenewal(ctx context.Context, planID int64) (*PlanSummary, error) {
	var p PlanSummary
	err := database.ScopedDB(ctx, r.db).
		Table("membership_plans").
		Select("id, gym_id, duration_days, is_active").
		Where("id = ? AND deleted_at IS NULL", planID).
		First(&p).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &p, err
}
