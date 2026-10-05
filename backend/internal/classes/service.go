package classes

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"gorm.io/gorm"

	"gymcrm/internal/database"
)

// Service holds all classes/booking business logic. Rules are specified in
// docs/FR-02-classes-booking.md; this file implements that document and the
// two should change together.
type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

// ─── Class types ──────────────────────────────────────────────────────────────

func (s *Service) CreateClassType(ctx context.Context, req CreateClassTypeRequest) (*ClassTypeResponse, error) {
	if err := validateCreateClassType(req); err != nil {
		return nil, err
	}
	tc := database.MustGetTenant(ctx)
	ct := &ClassType{
		GymID:           tc.GymID(),
		Name:            req.Name,
		Description:     optionalText(req.Description),
		DurationMinutes: req.DurationMinutes,
		DefaultCapacity: req.DefaultCapacity,
		IsActive:        true,
	}
	if err := s.repo.CreateClassType(ctx, ct); err != nil {
		return nil, fmt.Errorf("create class type: %w", err)
	}
	return toClassTypeResponse(*ct), nil
}

// UpdateClassType edits a class type. Only provided fields change. This never
// touches any schedule or session already created from it — those hold their
// own snapshot of duration/capacity taken at creation time (FR-02 §0.1), so
// editing the class type only affects what gets created from it going forward.
func (s *Service) UpdateClassType(ctx context.Context, id int64, req UpdateClassTypeRequest) (*ClassTypeResponse, error) {
	if err := validateUpdateClassType(req); err != nil {
		return nil, err
	}
	existing, err := s.repo.FindClassType(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("update class type: find: %w", err)
	}
	if existing == nil {
		return nil, ErrClassTypeNotFound
	}

	mut := map[string]any{}
	if req.Name != nil {
		mut["name"] = strings.TrimSpace(*req.Name)
	}
	if req.Description != nil {
		mut["description"] = optionalText(*req.Description)
	}
	if req.DurationMinutes != nil {
		mut["duration_minutes"] = *req.DurationMinutes
	}
	if req.DefaultCapacity != nil {
		mut["default_capacity"] = *req.DefaultCapacity
	}
	if req.IsActive != nil {
		mut["is_active"] = *req.IsActive
	}
	if len(mut) > 0 {
		if err := s.repo.UpdateClassType(ctx, id, mut); err != nil {
			return nil, fmt.Errorf("update class type: %w", err)
		}
	}

	updated, err := s.repo.FindClassType(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("update class type: reload: %w", err)
	}
	return toClassTypeResponse(*updated), nil
}

func (s *Service) ListClassTypes(ctx context.Context, activeOnly bool) ([]ClassTypeResponse, error) {
	types, err := s.repo.ListClassTypes(ctx, activeOnly)
	if err != nil {
		return nil, fmt.Errorf("list class types: %w", err)
	}
	out := make([]ClassTypeResponse, 0, len(types))
	for _, t := range types {
		out = append(out, *toClassTypeResponse(t))
	}
	return out, nil
}

// ─── Class schedules ──────────────────────────────────────────────────────────

func (s *Service) CreateSchedule(ctx context.Context, req CreateScheduleRequest) (*ScheduleResponse, error) {
	startTime, from, until, err := validateCreateSchedule(req)
	if err != nil {
		return nil, err
	}

	ct, err := s.repo.FindClassType(ctx, req.ClassTypeID)
	if err != nil {
		return nil, fmt.Errorf("create schedule: find class type: %w", err)
	}
	if ct == nil {
		return nil, ErrClassTypeNotFound
	}
	if !ct.IsActive {
		return nil, ErrClassTypeInactive
	}

	duration := req.DurationMinutes
	if duration <= 0 {
		duration = ct.DurationMinutes
	}
	capacity := req.Capacity
	if capacity <= 0 {
		capacity = ct.DefaultCapacity
	}

	tc := database.MustGetTenant(ctx)
	sched := &ClassSchedule{
		GymID:           tc.GymID(),
		ClassTypeID:     ct.ID,
		DayOfWeek:       req.DayOfWeek,
		StartTime:       startTime,
		DurationMinutes: duration,
		Capacity:        capacity,
		TrainerUserID:   req.TrainerUserID,
		EffectiveFrom:   from,
		EffectiveUntil:  until,
		IsActive:        true,
	}
	if err := s.repo.CreateSchedule(ctx, sched); err != nil {
		return nil, fmt.Errorf("create schedule: %w", err)
	}

	// Generate the first rolling window immediately so the schedule is
	// bookable right away rather than waiting for the next generation run.
	windowEnd := today().AddDate(0, 0, GenerationWindowDays)
	if _, err := s.repo.GenerateFromSchedule(ctx, *sched, from, windowEnd); err != nil {
		return nil, fmt.Errorf("create schedule: generate sessions: %w", err)
	}

	return &ScheduleResponse{
		ID: sched.ID, ClassTypeID: sched.ClassTypeID, ClassTypeName: ct.Name,
		DayOfWeek: sched.DayOfWeek, StartTime: sched.StartTime,
		DurationMinutes: sched.DurationMinutes, Capacity: sched.Capacity,
		TrainerUserID: sched.TrainerUserID,
		EffectiveFrom: sched.EffectiveFrom, EffectiveUntil: sched.EffectiveUntil,
		IsActive: sched.IsActive,
	}, nil
}

func (s *Service) ListSchedules(ctx context.Context, activeOnly bool) ([]ScheduleResponse, error) {
	rows, err := s.repo.ListSchedules(ctx, activeOnly)
	if err != nil {
		return nil, fmt.Errorf("list schedules: %w", err)
	}
	out := make([]ScheduleResponse, 0, len(rows))
	for _, r := range rows {
		out = append(out, ScheduleResponse{
			ID: r.ID, ClassTypeID: r.ClassTypeID, ClassTypeName: r.ClassTypeName,
			DayOfWeek: r.DayOfWeek, StartTime: r.StartTime,
			DurationMinutes: r.DurationMinutes, Capacity: r.Capacity,
			TrainerUserID: r.TrainerUserID, TrainerName: r.TrainerName,
			EffectiveFrom: r.EffectiveFrom, EffectiveUntil: r.EffectiveUntil,
			IsActive: r.IsActive,
		})
	}
	return out, nil
}

// GenerateUpcomingSessions extends materialization for every active schedule
// by another rolling window. Intended to run on a daily cadence (cron/manual
// trigger — no scheduler exists yet in this codebase, so this is exposed as
// an endpoint for now). Safe to call as often as desired: idempotent per
// schedule via the ON CONFLICT in the repository. FR-02 §2.
func (s *Service) GenerateUpcomingSessions(ctx context.Context) (int, error) {
	schedules, err := s.repo.ListSchedules(ctx, true)
	if err != nil {
		return 0, fmt.Errorf("generate sessions: list schedules: %w", err)
	}
	windowEnd := today().AddDate(0, 0, GenerationWindowDays)
	total := 0
	for _, sr := range schedules {
		n, err := s.repo.GenerateFromSchedule(ctx, sr.ClassSchedule, today(), windowEnd)
		if err != nil {
			return total, fmt.Errorf("generate sessions: schedule %d: %w", sr.ID, err)
		}
		total += n
	}
	return total, nil
}

// ─── Ad-hoc sessions ──────────────────────────────────────────────────────────

func (s *Service) CreateAdHocSession(ctx context.Context, req CreateAdHocSessionRequest) (*SessionResponse, error) {
	date, startTime, err := validateAdHocSession(req)
	if err != nil {
		return nil, err
	}
	ct, err := s.repo.FindClassType(ctx, req.ClassTypeID)
	if err != nil {
		return nil, fmt.Errorf("create session: find class type: %w", err)
	}
	if ct == nil {
		return nil, ErrClassTypeNotFound
	}

	duration := req.DurationMinutes
	if duration <= 0 {
		duration = ct.DurationMinutes
	}
	capacity := req.Capacity
	if capacity <= 0 {
		capacity = ct.DefaultCapacity
	}

	tc := database.MustGetTenant(ctx)
	session := &ClassSession{
		GymID: tc.GymID(), ScheduleID: nil, ClassTypeID: ct.ID,
		SessionDate: date, StartTime: startTime, DurationMinutes: duration,
		Capacity: capacity, TrainerUserID: req.TrainerUserID, Status: SessionScheduled,
	}
	if err := s.repo.CreateSession(ctx, session); err != nil {
		return nil, fmt.Errorf("create session: %w", err)
	}
	return s.session(ctx, session.ID)
}

// ─── Sessions ─────────────────────────────────────────────────────────────────

func (s *Service) ListSessions(ctx context.Context, from, to time.Time) ([]SessionResponse, error) {
	rows, err := s.repo.ListSessions(ctx, from, to)
	if err != nil {
		return nil, fmt.Errorf("list sessions: %w", err)
	}
	out := make([]SessionResponse, 0, len(rows))
	for _, r := range rows {
		out = append(out, toSessionResponse(r))
	}
	return out, nil
}

func (s *Service) session(ctx context.Context, id int64) (*SessionResponse, error) {
	row, err := s.repo.sessionRowByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("get session: %w", err)
	}
	if row == nil {
		return nil, ErrSessionNotFound
	}
	resp := toSessionResponse(*row)
	return &resp, nil
}

func (s *Service) Session(ctx context.Context, id int64) (*SessionResponse, error) {
	return s.session(ctx, id)
}

// UpdateSession edits ONE materialized session — substitute trainer, one-off
// capacity change — without touching the recurrence rule. FR-02 §3.1.
func (s *Service) UpdateSession(ctx context.Context, id int64, req UpdateSessionRequest) (*SessionResponse, error) {
	existing, err := s.repo.FindSession(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("update session: find: %w", err)
	}
	if existing == nil {
		return nil, ErrSessionNotFound
	}
	if existing.Status != SessionScheduled {
		return nil, fmt.Errorf("cannot edit a %s session", existing.Status)
	}

	mut := map[string]any{}
	if req.Capacity != nil && *req.Capacity > 0 {
		mut["capacity"] = *req.Capacity
	}
	if req.TrainerUserID != nil {
		mut["trainer_user_id"] = *req.TrainerUserID
	}
	if len(mut) > 0 {
		if err := s.repo.UpdateSession(ctx, id, mut); err != nil {
			return nil, fmt.Errorf("update session: %w", err)
		}
	}
	return s.session(ctx, id)
}

// CancelSession cancels a session and every active booking on it. FR-02 §3.3.
func (s *Service) CancelSession(ctx context.Context, id int64) (*SessionResponse, error) {
	existing, err := s.repo.FindSession(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("cancel session: find: %w", err)
	}
	if existing == nil {
		return nil, ErrSessionNotFound
	}
	switch existing.Status {
	case SessionCancelled:
		return nil, ErrSessionAlreadyCancelled
	case SessionCompleted:
		return nil, ErrCannotCancelCompleted
	}

	if _, err := s.repo.CancelSessionWithBookings(ctx, id); err != nil {
		return nil, fmt.Errorf("cancel session: %w", err)
	}
	return s.session(ctx, id)
}

// CompleteSession marks a session as having run. Does NOT auto-mark any
// booking attended — attendance is recorded explicitly per booking.
// FR-02 §4.4.
func (s *Service) CompleteSession(ctx context.Context, id int64) (*SessionResponse, error) {
	existing, err := s.repo.FindSession(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("complete session: find: %w", err)
	}
	if existing == nil {
		return nil, ErrSessionNotFound
	}
	if existing.Status == SessionCancelled {
		return nil, ErrSessionAlreadyCancelled
	}
	if err := s.repo.UpdateSession(ctx, id, map[string]any{"status": SessionCompleted}); err != nil {
		return nil, fmt.Errorf("complete session: %w", err)
	}
	return s.session(ctx, id)
}

// ─── Bookings ─────────────────────────────────────────────────────────────────

// Book places a member into a session, or onto its waitlist if full.
//
// The capacity check and the insert happen inside one transaction with the
// session row locked FOR UPDATE (repository.findSessionForUpdate), so two
// concurrent bookings for the last seat cannot both succeed. FR-02 §4.1.
func (s *Service) Book(ctx context.Context, sessionID int64, req CreateBookingRequest) (*BookingResult, error) {
	if req.MemberID <= 0 {
		return nil, fmt.Errorf("member_id is required")
	}
	tc := database.MustGetTenant(ctx)

	status, exists, err := s.repo.FindMemberStatus(ctx, req.MemberID)
	if err != nil {
		return nil, fmt.Errorf("book: find member: %w", err)
	}
	if !exists {
		return nil, ErrMemberNotFound
	}
	if status == "frozen" {
		return nil, ErrMemberFrozen
	}
	if status == "terminated" {
		return nil, ErrMemberTerminated
	}

	var bookingID int64
	err = s.repo.DB().Transaction(func(tx *gorm.DB) error {
		session, err := s.repo.findSessionForUpdate(ctx, tx, sessionID)
		if err != nil {
			return err
		}
		if session == nil {
			return ErrSessionNotFound
		}
		if session.Status != SessionScheduled {
			return ErrSessionNotBookable
		}
		startsAt, err := session.startsAt()
		if err != nil {
			return fmt.Errorf("parse session start: %w", err)
		}
		if !time.Now().Before(startsAt) {
			return ErrSessionAlreadyStarted
		}

		if existing, err := s.repo.memberActiveBooking(ctx, tx, sessionID, req.MemberID); err != nil {
			return err
		} else if existing != nil {
			return ErrAlreadyBooked
		}

		booked, waitlisted, err := s.repo.countActiveBookings(ctx, tx, sessionID)
		if err != nil {
			return err
		}

		b := Booking{
			GymID: tc.GymID(), SessionID: sessionID, MemberID: req.MemberID,
		}
		if booked < session.Capacity {
			b.Status = BookingBooked
		} else {
			pos, err := s.repo.nextWaitlistPosition(ctx, tx, sessionID)
			if err != nil {
				return err
			}
			_ = waitlisted // counted for clarity; position is independently tracked
			b.Status = BookingWaitlisted
			b.WaitlistPosition = &pos
		}
		if err := tx.Create(&b).Error; err != nil {
			return err
		}
		bookingID = b.ID
		return nil
	})
	if err != nil {
		return nil, err
	}
	return s.bookingResult(ctx, bookingID, nil)
}

// Cancel cancels a booking. If it was an occupied (booked) slot, the oldest
// waitlisted member is promoted in the same transaction — freeing a slot
// without promoting, or promoting without a freed slot, must never happen
// independently. FR-02 §4.2, §4.3.
func (s *Service) Cancel(ctx context.Context, bookingID int64, req CancelBookingRequest) (*BookingResult, error) {
	var promotedID *int64

	err := s.repo.DB().Transaction(func(tx *gorm.DB) error {
		var b Booking
		if err := tx.Where("id = ?", bookingID).Take(&b).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrBookingNotFound
			}
			return err
		}
		if !b.isActive() {
			return ErrBookingAlreadyCancelled
		}

		session, err := s.repo.findSessionForUpdate(ctx, tx, b.SessionID)
		if err != nil {
			return err
		}
		if session == nil {
			return ErrSessionNotFound
		}

		reason := CancelReasonMember
		if startsAt, err := session.startsAt(); err == nil {
			if time.Until(startsAt) < CancellationWindowHrs*time.Hour {
				reason = CancelReasonLate
			}
		}

		wasBooked := b.Status == BookingBooked
		if err := tx.Model(&b).Updates(map[string]any{
			"status": BookingCancelled, "cancelled_at": time.Now(),
			"cancel_reason": reason, "updated_at": time.Now(),
		}).Error; err != nil {
			return err
		}
		_ = req.Reason // free-text reason has no dedicated column in v1; recorded via cancel_reason code only

		if !wasBooked {
			return nil // freeing a waitlist slot promotes nobody
		}

		next, err := s.repo.oldestWaitlisted(ctx, tx, b.SessionID)
		if err != nil {
			return err
		}
		if next == nil {
			return nil
		}
		if err := tx.Model(next).Updates(map[string]any{
			"status": BookingBooked, "waitlist_position": nil, "updated_at": time.Now(),
		}).Error; err != nil {
			return err
		}
		promotedID = &next.ID
		return nil
	})
	if err != nil {
		return nil, err
	}

	return s.bookingResult(ctx, bookingID, promotedID)
}

// MarkAttendance records whether a member showed up. Only valid once the
// session has started — "did they show up" isn't knowable earlier.
// FR-02 §4.4.
func (s *Service) MarkAttendance(ctx context.Context, bookingID int64, req MarkAttendanceRequest) (*BookingResult, error) {
	var b Booking
	if err := s.repo.DB().Where("id = ?", bookingID).Take(&b).Error; err != nil {
		return nil, ErrBookingNotFound
	}
	if b.Status != BookingBooked {
		return nil, fmt.Errorf("only a booked member can be marked attended or no-show")
	}

	session, err := s.repo.FindSession(ctx, b.SessionID)
	if err != nil {
		return nil, fmt.Errorf("mark attendance: find session: %w", err)
	}
	if session == nil {
		return nil, ErrSessionNotFound
	}
	if startsAt, err := session.startsAt(); err == nil && time.Now().Before(startsAt) {
		return nil, ErrCannotMarkBeforeSession
	}

	status := BookingNoShow
	if req.Attended {
		status = BookingAttended
	}
	if err := s.repo.DB().Model(&b).Update("status", status).Error; err != nil {
		return nil, fmt.Errorf("mark attendance: %w", err)
	}
	return s.bookingResult(ctx, bookingID, nil)
}

// ListMemberBookings returns a member's booking history, newest first.
// ListSessionBookings returns a session's roster: booked first, then
// waitlisted in FIFO order, then attended/no-show/cancelled by recency.
func (s *Service) ListSessionBookings(ctx context.Context, sessionID int64) ([]BookingResponse, error) {
	rows, err := s.repo.ListSessionBookings(ctx, sessionID)
	if err != nil {
		return nil, fmt.Errorf("list session bookings: %w", err)
	}
	out := make([]BookingResponse, 0, len(rows))
	for _, r := range rows {
		out = append(out, toBookingResponse(r))
	}
	return out, nil
}

func (s *Service) ListMemberBookings(ctx context.Context, memberID int64) ([]BookingResponse, error) {
	tc := database.MustGetTenant(ctx)
	var rows []bookingRow
	err := s.repo.DB().WithContext(ctx).
		Table("bookings").
		Select(`bookings.*, m.first_name || ' ' || m.last_name AS member_name`).
		Joins("JOIN members m ON m.id = bookings.member_id").
		Where("bookings.member_id = ? AND bookings.gym_id = ?", memberID, tc.GymID()).
		Order("bookings.created_at DESC").
		Scan(&rows).Error
	if err != nil {
		return nil, fmt.Errorf("list member bookings: %w", err)
	}
	out := make([]BookingResponse, 0, len(rows))
	for _, r := range rows {
		out = append(out, toBookingResponse(r))
	}
	return out, nil
}

func (s *Service) bookingResult(ctx context.Context, bookingID int64, promotedID *int64) (*BookingResult, error) {
	row, err := s.repo.bookingRowByID(ctx, s.repo.DB(), bookingID)
	if err != nil {
		return nil, fmt.Errorf("load booking: %w", err)
	}
	if row == nil {
		return nil, ErrBookingNotFound
	}
	sessionResp, err := s.session(ctx, row.SessionID)
	if err != nil {
		return nil, err
	}

	result := &BookingResult{Booking: toBookingResponse(*row), Session: *sessionResp}
	if promotedID != nil {
		pRow, err := s.repo.bookingRowByID(ctx, s.repo.DB(), *promotedID)
		if err == nil && pRow != nil {
			resp := toBookingResponse(*pRow)
			result.Promoted = &resp
		}
	}
	return result, nil
}

// ─── mapping helpers ──────────────────────────────────────────────────────────

func toClassTypeResponse(ct ClassType) *ClassTypeResponse {
	return &ClassTypeResponse{
		ID: ct.ID, Name: ct.Name, Description: ct.Description,
		DurationMinutes: ct.DurationMinutes, DefaultCapacity: ct.DefaultCapacity,
		IsActive: ct.IsActive, CreatedAt: ct.CreatedAt,
	}
}

func toSessionResponse(r sessionRow) SessionResponse {
	return SessionResponse{
		ID: r.ID, ScheduleID: r.ScheduleID, ClassTypeID: r.ClassTypeID,
		ClassTypeName: r.ClassTypeName, SessionDate: r.SessionDate, StartTime: r.StartTime,
		DurationMinutes: r.DurationMinutes, Capacity: r.Capacity,
		TrainerUserID: r.TrainerUserID, TrainerName: r.TrainerName,
		Status: r.Status, BookedCount: r.BookedCount, WaitlistCount: r.WaitlistCount,
	}
}

func toBookingResponse(r bookingRow) BookingResponse {
	return BookingResponse{
		ID: r.ID, SessionID: r.SessionID, MemberID: r.MemberID, MemberName: r.MemberName,
		Status: r.Status, WaitlistPosition: r.WaitlistPosition,
		BookedAt: r.BookedAt, CancelledAt: r.CancelledAt, CancelReason: r.CancelReason,
	}
}

func optionalText(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}
