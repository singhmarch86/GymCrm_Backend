package dashboard

import (
	"context"
	"time"

	"gymcrm/internal/attendance"
	"gymcrm/internal/database"
	"gymcrm/internal/members"
	"gymcrm/internal/renewals"

	"gorm.io/gorm"
)

type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository {
	return &Repository{
		db: db,
	}
}

func (r *Repository) GetDashboard(ctx context.Context) (*DashboardResponse, error) {
	stats := &DashboardResponse{}

	// ------------------------------------------------------------------
	// Members
	// ------------------------------------------------------------------

	if err := database.ScopedDB(ctx, r.db).
		Model(&members.Member{}).
		Count(&stats.TotalMembers).Error; err != nil {
		return nil, err
	}

	if err := database.ScopedDB(ctx, r.db).
		Model(&members.Member{}).
		Where("status = ?", "active").
		Count(&stats.ActiveMembers).Error; err != nil {
		return nil, err
	}

	if err := database.ScopedDB(ctx, r.db).
		Model(&members.Member{}).
		Where("status = ?", "expired").
		Count(&stats.ExpiredMembers).Error; err != nil {
		return nil, err
	}

	today := time.Now().Truncate(24 * time.Hour)

	next7Days := today.AddDate(0, 0, 7)
	next30Days := today.AddDate(0, 0, 30)

	if err := database.ScopedDB(ctx, r.db).
		Model(&members.Member{}).
		Where("expiry_date BETWEEN ? AND ?", today, next7Days).
		Count(&stats.Expiring7Days).Error; err != nil {
		return nil, err
	}

	if err := database.ScopedDB(ctx, r.db).
		Model(&members.Member{}).
		Where("expiry_date BETWEEN ? AND ?", today, next30Days).
		Count(&stats.Expiring30Days).Error; err != nil {
		return nil, err
	}

	// ------------------------------------------------------------------
	// Renewals
	// ------------------------------------------------------------------

	if err := database.ScopedDB(ctx, r.db).
		Model(&renewals.Renewal{}).
		Where("renewal_date = CURRENT_DATE").
		Count(&stats.RenewalsToday).Error; err != nil {
		return nil, err
	}

	if err := database.ScopedDB(ctx, r.db).
		Model(&renewals.Renewal{}).
		Where("DATE_TRUNC('month', renewal_date) = DATE_TRUNC('month', CURRENT_DATE)").
		Count(&stats.RenewalsThisMonth).Error; err != nil {
		return nil, err
	}

	if err := database.ScopedDB(ctx, r.db).
		Table("payments").
		Select("COALESCE(SUM(amount_in_paise),0)").
		Where("status = 'paid' AND DATE_TRUNC('month', paid_date) = DATE_TRUNC('month', CURRENT_DATE)").
		Scan(&stats.RevenueThisMonth).Error; err != nil {
		return nil, err
	}

	// ------------------------------------------------------------------
	// Attendance
	// ------------------------------------------------------------------

	if err := database.ScopedDB(ctx, r.db).
		Model(&attendance.Attendance{}).
		Where("checked_in_date = CURRENT_DATE").
		Count(&stats.AttendanceToday).Error; err != nil {
		return nil, err
	}

	// ------------------------------------------------------------------
	// Churn warnings — active members with no check-in in N days
	// ------------------------------------------------------------------

	var err error
	if stats.Inactive7Days, err = r.countInactiveMembers(ctx, 7); err != nil {
		return nil, err
	}
	if stats.Inactive14Days, err = r.countInactiveMembers(ctx, 14); err != nil {
		return nil, err
	}
	if stats.Inactive30Days, err = r.countInactiveMembers(ctx, 30); err != nil {
		return nil, err
	}

	return stats, nil
}

// countInactiveMembers counts active members who have not checked in since
// the given cutoff. Same "NOT IN the set of member IDs seen since cutoff"
// shape as attendance.Repository.FindInactiveMemberIDs (kept separate
// rather than called directly — that method returns IDs for a future
// retention job, this needs only a count scoped through the dashboard's
// own database.ScopedDB(ctx, r.db) calls, consistent with the rest of this
// file).
func (r *Repository) countInactiveMembers(ctx context.Context, days int) (int64, error) {
	cutoff := time.Now().UTC().Truncate(24*time.Hour).AddDate(0, 0, -days)

	var recentlySeenIDs []int64
	if err := database.ScopedDB(ctx, r.db).
		Table("attendance").
		Select("DISTINCT member_id").
		Where("checked_in_date >= ?", cutoff).
		Pluck("member_id", &recentlySeenIDs).Error; err != nil {
		return 0, err
	}

	q := database.ScopedDB(ctx, r.db).
		Table("members").
		Where("deleted_at IS NULL AND status = 'active'")
	if len(recentlySeenIDs) > 0 {
		q = q.Where("id NOT IN ?", recentlySeenIDs)
	}

	var count int64
	err := q.Count(&count).Error
	return count, err
}
