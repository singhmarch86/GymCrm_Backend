package classes

import (
	"context"
	"errors"
	"time"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"gymcrm/internal/database"
)

// Repository handles all classes/booking DB operations.
//
// TENANT ISOLATION: every query starts from database.ScopedDB(ctx, r.db) or
// explicitly qualifies gym_id on joined queries, same convention as
// internal/lifecycle and internal/renewals.
//
// CONCURRENCY: session capacity and waitlist promotion are the two places two
// staff members (or a member double-tapping "book") could race. Both go
// through `SELECT ... FOR UPDATE` on the session row inside a transaction, so
// the capacity check and the insert that follows it are atomic — no two
// bookings can both observe "1 seat left" and both take it.
type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository { return &Repository{db: db} }

// DB exposes the underlying connection for service-level transactions that
// span more than one repository method (Book, Cancel).
func (r *Repository) DB() *gorm.DB { return r.db }

// ─── Class types ──────────────────────────────────────────────────────────────

func (r *Repository) CreateClassType(ctx context.Context, ct *ClassType) error {
	return database.ScopedDB(ctx, r.db).Create(ct).Error
}

func (r *Repository) FindClassType(ctx context.Context, id int64) (*ClassType, error) {
	var ct ClassType
	err := database.ScopedDB(ctx, r.db).
		Where("id = ? AND deleted_at IS NULL", id).Take(&ct).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &ct, err
}

func (r *Repository) ListClassTypes(ctx context.Context, activeOnly bool) ([]ClassType, error) {
	q := database.ScopedDB(ctx, r.db).Where("deleted_at IS NULL")
	if activeOnly {
		q = q.Where("is_active = true")
	}
	var out []ClassType
	err := q.Order("name").Find(&out).Error
	return out, err
}

// ─── Class schedules ──────────────────────────────────────────────────────────

func (r *Repository) CreateSchedule(ctx context.Context, s *ClassSchedule) error {
	return database.ScopedDB(ctx, r.db).Create(s).Error
}

func (r *Repository) FindSchedule(ctx context.Context, id int64) (*ClassSchedule, error) {
	var s ClassSchedule
	err := database.ScopedDB(ctx, r.db).
		Where("id = ? AND deleted_at IS NULL", id).Take(&s).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &s, err
}

type scheduleRow struct {
	ClassSchedule
	ClassTypeName string
	TrainerName   *string
}

func (r *Repository) ListSchedules(ctx context.Context, activeOnly bool) ([]scheduleRow, error) {
	tc := database.MustGetTenant(ctx)
	q := r.db.WithContext(ctx).
		Table("class_schedules").
		Select(`class_schedules.*, ct.name AS class_type_name, u.name AS trainer_name`).
		Joins("JOIN class_types ct ON ct.id = class_schedules.class_type_id").
		Joins("LEFT JOIN users u ON u.id = class_schedules.trainer_user_id").
		Where("class_schedules.gym_id = ? AND class_schedules.deleted_at IS NULL", tc.GymID())
	if activeOnly {
		q = q.Where("class_schedules.is_active = true")
	}
	var out []scheduleRow
	err := q.Order("class_schedules.day_of_week, class_schedules.start_time").Scan(&out).Error
	return out, err
}

// ─── Class sessions ───────────────────────────────────────────────────────────

func (r *Repository) CreateSession(ctx context.Context, s *ClassSession) error {
	return database.ScopedDB(ctx, r.db).Create(s).Error
}

// GenerateFromSchedule materializes sessions for one schedule across
// [from, to], skipping dates already generated. Idempotent by construction:
// ON CONFLICT DO NOTHING against idx_class_sessions_schedule_date means
// calling this twice for the same range is always safe. FR-02 §2.
func (r *Repository) GenerateFromSchedule(ctx context.Context, s ClassSchedule, from, to time.Time) (int, error) {
	tc := database.MustGetTenant(ctx)
	created := 0

	for d := from; !d.After(to); d = d.AddDate(0, 0, 1) {
		if int(d.Weekday()) != s.DayOfWeek {
			continue
		}
		if d.Before(s.EffectiveFrom) {
			continue
		}
		if s.EffectiveUntil != nil && d.After(*s.EffectiveUntil) {
			continue
		}

		res := r.db.WithContext(ctx).Exec(`
			INSERT INTO class_sessions
				(gym_id, schedule_id, class_type_id, session_date, start_time,
				 duration_minutes, capacity, trainer_user_id, status)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'scheduled')
			ON CONFLICT (schedule_id, session_date) WHERE schedule_id IS NOT NULL
			DO NOTHING`,
			tc.GymID(), s.ID, s.ClassTypeID, d, s.StartTime,
			s.DurationMinutes, s.Capacity, s.TrainerUserID,
		)
		if res.Error != nil {
			return created, res.Error
		}
		created += int(res.RowsAffected)
	}
	return created, nil
}

func (r *Repository) FindSession(ctx context.Context, id int64) (*ClassSession, error) {
	var s ClassSession
	err := database.ScopedDB(ctx, r.db).Where("id = ?", id).Take(&s).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &s, err
}

// findSessionForUpdate locks the session row so a concurrent booking cannot
// observe stale capacity. Must be called with a *gorm.DB bound to a
// transaction (tx), never the plain repository db.
func (r *Repository) findSessionForUpdate(ctx context.Context, tx *gorm.DB, id int64) (*ClassSession, error) {
	tc := database.MustGetTenant(ctx)
	var s ClassSession
	err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("id = ? AND gym_id = ?", id, tc.GymID()).
		Take(&s).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &s, err
}

type sessionRow struct {
	ClassSession
	ClassTypeName string
	TrainerName   *string
	BookedCount   int
	WaitlistCount int
}

// ListSessions returns sessions in a date range with live booking counts —
// the dominant read for "what's on today/this week." FR-02 §3, table comment.
func (r *Repository) ListSessions(ctx context.Context, from, to time.Time) ([]sessionRow, error) {
	tc := database.MustGetTenant(ctx)
	var out []sessionRow
	err := r.db.WithContext(ctx).
		Table("class_sessions").
		Select(`class_sessions.*, ct.name AS class_type_name, u.name AS trainer_name,
		        COALESCE(bc.booked, 0)   AS booked_count,
		        COALESCE(bc.waitlisted, 0) AS waitlist_count`).
		Joins("JOIN class_types ct ON ct.id = class_sessions.class_type_id").
		Joins("LEFT JOIN users u ON u.id = class_sessions.trainer_user_id").
		Joins(`LEFT JOIN (
			SELECT session_id,
			       count(*) FILTER (WHERE status = 'booked')     AS booked,
			       count(*) FILTER (WHERE status = 'waitlisted') AS waitlisted
			FROM bookings GROUP BY session_id
		) bc ON bc.session_id = class_sessions.id`).
		Where("class_sessions.gym_id = ? AND class_sessions.session_date BETWEEN ? AND ?", tc.GymID(), from, to).
		Order("class_sessions.session_date, class_sessions.start_time").
		Scan(&out).Error
	return out, err
}

func (r *Repository) sessionRowByID(ctx context.Context, id int64) (*sessionRow, error) {
	tc := database.MustGetTenant(ctx)
	var row sessionRow
	err := r.db.WithContext(ctx).
		Table("class_sessions").
		Select(`class_sessions.*, ct.name AS class_type_name, u.name AS trainer_name,
		        COALESCE(bc.booked, 0)   AS booked_count,
		        COALESCE(bc.waitlisted, 0) AS waitlist_count`).
		Joins("JOIN class_types ct ON ct.id = class_sessions.class_type_id").
		Joins("LEFT JOIN users u ON u.id = class_sessions.trainer_user_id").
		Joins(`LEFT JOIN (
			SELECT session_id,
			       count(*) FILTER (WHERE status = 'booked')     AS booked,
			       count(*) FILTER (WHERE status = 'waitlisted') AS waitlisted
			FROM bookings GROUP BY session_id
		) bc ON bc.session_id = class_sessions.id`).
		Where("class_sessions.id = ? AND class_sessions.gym_id = ?", id, tc.GymID()).
		Take(&row).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &row, err
}

func (r *Repository) UpdateSession(ctx context.Context, id int64, mut map[string]any) error {
	mut["updated_at"] = time.Now()
	return database.ScopedDB(ctx, r.db).
		Table("class_sessions").Where("id = ?", id).Updates(mut).Error
}

// CancelSessionWithBookings cancels a session and every active booking on it
// in one transaction — a session cancelled with its bookings still "booked"
// is the inconsistency FR-02 §3.3 exists to prevent.
func (r *Repository) CancelSessionWithBookings(ctx context.Context, sessionID int64) (int64, error) {
	tc := database.MustGetTenant(ctx)
	var affected int64

	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Table("class_sessions").
			Where("id = ? AND gym_id = ?", sessionID, tc.GymID()).
			Updates(map[string]any{"status": SessionCancelled, "updated_at": time.Now()}).Error; err != nil {
			return err
		}
		res := tx.Table("bookings").
			Where("session_id = ? AND gym_id = ? AND status IN ('booked','waitlisted')", sessionID, tc.GymID()).
			Updates(map[string]any{
				"status":        BookingCancelled,
				"cancelled_at":  time.Now(),
				"cancel_reason": CancelReasonSessionCancelled,
				"updated_at":    time.Now(),
			})
		affected = res.RowsAffected
		return res.Error
	})
	return affected, err
}

// ─── Bookings ─────────────────────────────────────────────────────────────────

// ListSessionBookings returns every booking on a session — the roster a
// trainer or front-desk staff needs to see: who's in, who's waitlisted and at
// what position, who cancelled or didn't show. Ordered so the active roster
// reads first: booked, then waitlisted by position, then the rest by recency.
func (r *Repository) ListSessionBookings(ctx context.Context, sessionID int64) ([]bookingRow, error) {
	tc := database.MustGetTenant(ctx)
	var rows []bookingRow
	err := r.db.WithContext(ctx).
		Table("bookings").
		Select(`bookings.*, m.first_name || ' ' || m.last_name AS member_name`).
		Joins("JOIN members m ON m.id = bookings.member_id").
		Where("bookings.session_id = ? AND bookings.gym_id = ?", sessionID, tc.GymID()).
		Order(`CASE bookings.status
		         WHEN 'booked' THEN 0
		         WHEN 'waitlisted' THEN 1
		         WHEN 'attended' THEN 2
		         WHEN 'no_show' THEN 3
		         ELSE 4 END,
		       bookings.waitlist_position ASC NULLS LAST,
		       bookings.created_at ASC`).
		Scan(&rows).Error
	return rows, err
}

func (r *Repository) memberActiveBooking(ctx context.Context, tx *gorm.DB, sessionID, memberID int64) (*Booking, error) {
	tc := database.MustGetTenant(ctx)
	var b Booking
	err := tx.Where(`session_id = ? AND member_id = ? AND gym_id = ? AND status IN ('booked','waitlisted')`,
		sessionID, memberID, tc.GymID()).Take(&b).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &b, err
}

// countActiveBookings returns booked and waitlisted counts, read inside the
// same transaction that holds the session's row lock — this is what makes
// the capacity check race-free. Must be called after findSessionForUpdate.
func (r *Repository) countActiveBookings(ctx context.Context, tx *gorm.DB, sessionID int64) (booked, waitlisted int, err error) {
	type row struct {
		Booked     int
		Waitlisted int
	}
	var out row
	err = tx.Raw(`
		SELECT
			count(*) FILTER (WHERE status = 'booked')     AS booked,
			count(*) FILTER (WHERE status = 'waitlisted') AS waitlisted
		FROM bookings WHERE session_id = ?`, sessionID).Scan(&out).Error
	return out.Booked, out.Waitlisted, err
}

func (r *Repository) nextWaitlistPosition(ctx context.Context, tx *gorm.DB, sessionID int64) (int, error) {
	var max *int
	err := tx.Raw(`SELECT max(waitlist_position) FROM bookings WHERE session_id = ? AND status = 'waitlisted'`, sessionID).
		Scan(&max).Error
	if err != nil {
		return 0, err
	}
	if max == nil {
		return 1, nil
	}
	return *max + 1, nil
}

func (r *Repository) oldestWaitlisted(ctx context.Context, tx *gorm.DB, sessionID int64) (*Booking, error) {
	var b Booking
	err := tx.Where("session_id = ? AND status = 'waitlisted'", sessionID).
		Order("waitlist_position ASC").
		Take(&b).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &b, err
}

// bookingRow denormalises member name for display, matching the
// lifecycle.eventRow pattern.
type bookingRow struct {
	Booking
	MemberName string
}

func (r *Repository) bookingRowByID(ctx context.Context, tx *gorm.DB, id int64) (*bookingRow, error) {
	var row bookingRow
	err := tx.Table("bookings").
		Select(`bookings.*, m.first_name || ' ' || m.last_name AS member_name`).
		Joins("JOIN members m ON m.id = bookings.member_id").
		Where("bookings.id = ?", id).
		Take(&row).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &row, err
}

// FindMemberStatus is the narrow lookup booking needs from members — status
// only, so this module has no business touching contact details. Mirrors
// lifecycle.memberSnapshot's narrowness for the same reason.
func (r *Repository) FindMemberStatus(ctx context.Context, memberID int64) (status string, exists bool, err error) {
	err = database.ScopedDB(ctx, r.db).
		Table("members").
		Select("status").
		Where("id = ? AND deleted_at IS NULL", memberID).
		Take(&status).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return "", false, nil
	}
	return status, err == nil, err
}
