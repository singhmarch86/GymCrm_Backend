package referrals

import (
	"context"
	"errors"
	"time"

	"gorm.io/gorm"

	"gymcrm/internal/database"
)

type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository { return &Repository{db: db} }

func (r *Repository) Create(ctx context.Context, ref *Referral) error {
	return database.ScopedDB(ctx, r.db).Create(ref).Error
}

func (r *Repository) FindByID(ctx context.Context, id int64) (*Referral, error) {
	var ref Referral
	err := database.ScopedDB(ctx, r.db).Where("id = ?", id).Take(&ref).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &ref, err
}

func (r *Repository) Update(ctx context.Context, id int64, mut map[string]any) error {
	mut["updated_at"] = time.Now()
	return database.ScopedDB(ctx, r.db).
		Table("referrals").Where("id = ?", id).Updates(mut).Error
}

// FindMember is the narrow members lookup this module needs — status and
// expiry only. Same narrowness convention as lifecycle.memberSnapshot.
func (r *Repository) FindMember(ctx context.Context, id int64) (*memberSnapshot, error) {
	var m memberSnapshot
	err := database.ScopedDB(ctx, r.db).
		Table("members").
		Select("id, status, expiry_date").
		Where("id = ? AND deleted_at IS NULL", id).
		Take(&m).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &m, err
}

// ExtendMemberExpiry adds days to a member's expiry_date — the referral
// reward payout. A narrow, direct write to members, same precedent as
// lifecycle's transaction-scoped member updates.
func (r *Repository) ExtendMemberExpiry(ctx context.Context, memberID int64, newExpiry time.Time) error {
	return database.ScopedDB(ctx, r.db).
		Table("members").Where("id = ?", memberID).
		Updates(map[string]any{"expiry_date": newExpiry, "updated_at": time.Now()}).Error
}

type referralRow struct {
	Referral
	ReferrerName      string
	CreatedByUserName string
}

func (r *Repository) List(ctx context.Context, referrerMemberID *int64) ([]referralRow, error) {
	tc := database.MustGetTenant(ctx)
	q := r.db.WithContext(ctx).
		Table("referrals").
		Select(`referrals.*,
		        rm.first_name || ' ' || rm.last_name AS referrer_name,
		        COALESCE(u.name, 'Unknown')          AS created_by_user_name`).
		Joins("JOIN members rm ON rm.id = referrals.referrer_member_id").
		Joins("LEFT JOIN users u ON u.id = referrals.created_by_user_id").
		Where("referrals.gym_id = ?", tc.GymID())
	if referrerMemberID != nil {
		q = q.Where("referrals.referrer_member_id = ?", *referrerMemberID)
	}
	var rows []referralRow
	err := q.Order("referrals.created_at DESC").Scan(&rows).Error
	return rows, err
}

func (r *Repository) rowByID(ctx context.Context, id int64) (*referralRow, error) {
	tc := database.MustGetTenant(ctx)
	var row referralRow
	err := r.db.WithContext(ctx).
		Table("referrals").
		Select(`referrals.*,
		        rm.first_name || ' ' || rm.last_name AS referrer_name,
		        COALESCE(u.name, 'Unknown')          AS created_by_user_name`).
		Joins("JOIN members rm ON rm.id = referrals.referrer_member_id").
		Joins("LEFT JOIN users u ON u.id = referrals.created_by_user_id").
		Where("referrals.id = ? AND referrals.gym_id = ?", id, tc.GymID()).
		Take(&row).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &row, err
}
