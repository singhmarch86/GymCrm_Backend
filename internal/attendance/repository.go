package attendance

import (
	"context"
	"time"

	"gorm.io/gorm"

	"gymcrm/internal/database"
	"gymcrm/internal/shared/pagination"
)

// Repository handles all attendance DB operations.
//
// TENANT ISOLATION:
//   1. Single-table queries use database.ScopedDB(ctx, r.db)
//   2. Joined queries use scopedAttendanceDB() which qualifies attendance.gym_id
//      to avoid "column reference gym_id is ambiguous" with joined members table
//   3. No Update or Delete methods — attendance is append-only
type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository {
	return &Repository{db: db}
}

// scopedAttendanceDB qualifies gym_id with the table name.
// Required for queries that JOIN members (which also has gym_id).
func (r *Repository) scopedAttendanceDB(ctx context.Context) *gorm.DB {
	tc := database.MustGetTenant(ctx)
	return r.db.WithContext(ctx).Where("attendance.gym_id = ?", tc.GymID())
}

// ─── Create ───────────────────────────────────────────────────────────────────

func (r *Repository) Create(ctx context.Context, a *Attendance) error {
	return database.ScopedDB(ctx, r.db).Create(a).Error
}

// ─── Duplicate check ──────────────────────────────────────────────────────────

// ExistsToday checks if a member has already checked in today (service-layer guard).
// The unique index is the DB-level guard for concurrent requests.
func (r *Repository) ExistsToday(ctx context.Context, memberID int64, today time.Time) (bool, error) {
	var count int64
	err := database.ScopedDB(ctx, r.db).
		Model(&Attendance{}).
		Where("member_id = ? AND checked_in_date = ?", memberID, today).
		Count(&count).Error
	return count > 0, err
}

// ─── Member validation ────────────────────────────────────────────────────────

// MemberExists checks if a member belongs to the tenant gym and is not deleted.
func (r *Repository) MemberExists(ctx context.Context, memberID int64) (bool, error) {
	var count int64
	err := database.ScopedDB(ctx, r.db).
		Table("members").
		Where("id = ? AND deleted_at IS NULL", memberID).
		Count(&count).Error
	return count > 0, err
}

// ─── Read — list queries ──────────────────────────────────────────────────────

// FindToday returns all check-ins for today, paginated.
// Index: idx_attendance_gym_date (gym_id, checked_in_date DESC)
func (r *Repository) FindToday(ctx context.Context, p pagination.Params) ([]AttendanceWithContext, int64, error) {
	today := time.Now().UTC().Truncate(24 * time.Hour)
	return r.findByDate(ctx, today, p)
}

// FindByDate returns all check-ins for a specific date, paginated.
func (r *Repository) FindByDate(ctx context.Context, date time.Time, p pagination.Params) ([]AttendanceWithContext, int64, error) {
	return r.findByDate(ctx, date, p)
}

func (r *Repository) findByDate(ctx context.Context, date time.Time, p pagination.Params) ([]AttendanceWithContext, int64, error) {
	q := r.scopedAttendanceDB(ctx).
		Table("attendance").
		Select(`attendance.*,
			members.first_name AS member_first_name,
			members.last_name  AS member_last_name`).
		Joins("JOIN members ON members.id = attendance.member_id").
		Where("attendance.checked_in_date = ?", date)

	var total int64
	if err := q.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var results []AttendanceWithContext
	err := q.
		Order("attendance.checked_in_at DESC").
		Limit(p.PerPage).
		Offset(p.Offset).
		Scan(&results).Error

	return results, total, err
}

// FindByMember returns attendance history for a specific member, paginated.
// Index: idx_attendance_gym_member_date (gym_id, member_id, checked_in_date DESC)
func (r *Repository) FindByMember(ctx context.Context, memberID int64, p pagination.Params) ([]AttendanceWithContext, int64, error) {
	q := r.scopedAttendanceDB(ctx).
		Table("attendance").
		Select(`attendance.*,
			members.first_name AS member_first_name,
			members.last_name  AS member_last_name`).
		Joins("JOIN members ON members.id = attendance.member_id").
		Where("attendance.member_id = ?", memberID)

	var total int64
	if err := q.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var results []AttendanceWithContext
	err := q.
		Order("attendance.checked_in_date DESC").
		Limit(p.PerPage).
		Offset(p.Offset).
		Scan(&results).Error

	return results, total, err
}

// FindRecent returns the last N check-ins across all members.
// Used for the gym owner's live activity feed.
func (r *Repository) FindRecent(ctx context.Context, limit int) ([]AttendanceWithContext, error) {
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	var results []AttendanceWithContext
	err := r.scopedAttendanceDB(ctx).
		Table("attendance").
		Select(`attendance.*,
			members.first_name AS member_first_name,
			members.last_name  AS member_last_name`).
		Joins("JOIN members ON members.id = attendance.member_id").
		Order("attendance.checked_in_at DESC").
		Limit(limit).
		Scan(&results).Error
	return results, err
}

// ─── Retention queries (used by Step 8) ──────────────────────────────────────

// FindInactiveMemberIDs returns IDs of members who have not checked in
// since the given cutoff date. Used by the retention job.
// Index: idx_attendance_gym_member_date supports the GROUP BY + HAVING pattern.
func (r *Repository) FindInactiveMemberIDs(ctx context.Context, since time.Time) ([]int64, error) {
	tc := database.MustGetTenant(ctx)

	// Subquery: member IDs who DID check in since the cutoff
	type result struct{ MemberID int64 }
	var activeIDs []int64
	if err := r.db.WithContext(ctx).
		Table("attendance").
		Select("DISTINCT member_id").
		Where("gym_id = ? AND checked_in_date >= ?", tc.GymID(), since).
		Pluck("member_id", &activeIDs).Error; err != nil {
		return nil, err
	}

	// Active members NOT in that list
	var inactiveIDs []int64
	q := r.db.WithContext(ctx).
		Table("members").
		Select("id").
		Where("gym_id = ? AND deleted_at IS NULL AND status = 'active'", tc.GymID())

	if len(activeIDs) > 0 {
		q = q.Where("id NOT IN ?", activeIDs)
	}

	err := q.Pluck("id", &inactiveIDs).Error
	return inactiveIDs, err
}
