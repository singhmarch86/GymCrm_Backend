package classes

import "time"

// ─── Class type ───────────────────────────────────────────────────────────────

// CreateClassTypeRequest is the payload for POST /api/v1/class-types.
// @Description Create a class type (Yoga, Zumba). gym_id comes from JWT.
type CreateClassTypeRequest struct {
	Name            string `json:"name"`             // required
	Description     string `json:"description"`      // optional
	DurationMinutes int    `json:"duration_minutes"`  // required, > 0
	DefaultCapacity int    `json:"default_capacity"`  // required, > 0
}

// UpdateClassTypeRequest is the payload for PUT /api/v1/class-types/{id}.
// All fields are optional — only the ones present are changed. Editing a
// class type never touches sessions already generated from it (FR-02 §0.1):
// this only affects new schedules/sessions created after the edit.
// @Description Edit a class type. Only provided fields are changed.
type UpdateClassTypeRequest struct {
	Name            *string `json:"name"`
	Description     *string `json:"description"`
	DurationMinutes *int    `json:"duration_minutes"`
	DefaultCapacity *int    `json:"default_capacity"`
	// IsActive toggles whether this type can be scheduled going forward.
	// Deactivating never cancels existing schedules or sessions.
	IsActive *bool `json:"is_active"`
}

// ClassTypeResponse is the full class type record.
// @Description A class type.
type ClassTypeResponse struct {
	ID              int64     `json:"id"`
	Name            string    `json:"name"`
	Description     *string   `json:"description,omitempty"`
	DurationMinutes int       `json:"duration_minutes"`
	DefaultCapacity int       `json:"default_capacity"`
	IsActive        bool      `json:"is_active"`
	CreatedAt       time.Time `json:"created_at"`
}

// ─── Class schedule ───────────────────────────────────────────────────────────

// CreateScheduleRequest is the payload for POST /api/v1/class-schedules.
// @Description Create a recurring schedule. Capacity/duration default from the class type if omitted.
type CreateScheduleRequest struct {
	ClassTypeID     int64  `json:"class_type_id"`             // required
	DayOfWeek       int    `json:"day_of_week"`                // required, 0-6
	StartTime       string `json:"start_time"`                 // required, "HH:MM"
	DurationMinutes int    `json:"duration_minutes"`           // optional, defaults from class type
	Capacity        int    `json:"capacity"`                   // optional, defaults from class type
	TrainerUserID   *int64 `json:"trainer_user_id"`             // optional — FR-02 §0.2
	EffectiveFrom   string `json:"effective_from"`             // optional, YYYY-MM-DD, defaults to today
	EffectiveUntil  string `json:"effective_until"`             // optional, YYYY-MM-DD, empty = open-ended
}

// ScheduleResponse is the full schedule record, with the class type name
// denormalised so the Flutter client doesn't need a second lookup.
// @Description A recurring class schedule.
type ScheduleResponse struct {
	ID              int64      `json:"id"`
	ClassTypeID     int64      `json:"class_type_id"`
	ClassTypeName   string     `json:"class_type_name"`
	DayOfWeek       int        `json:"day_of_week"`
	StartTime       string     `json:"start_time"`
	DurationMinutes int        `json:"duration_minutes"`
	Capacity        int        `json:"capacity"`
	TrainerUserID   *int64     `json:"trainer_user_id,omitempty"`
	TrainerName     *string    `json:"trainer_name,omitempty"`
	EffectiveFrom   time.Time  `json:"effective_from"`
	EffectiveUntil  *time.Time `json:"effective_until,omitempty"`
	IsActive        bool       `json:"is_active"`
}

// ─── Class session ────────────────────────────────────────────────────────────

// CreateAdHocSessionRequest creates a one-off session not tied to a recurrence.
// @Description Create a single ad-hoc session (no recurring schedule).
type CreateAdHocSessionRequest struct {
	ClassTypeID     int64  `json:"class_type_id"`     // required
	SessionDate     string `json:"session_date"`      // required, YYYY-MM-DD
	StartTime       string `json:"start_time"`        // required, "HH:MM"
	DurationMinutes int    `json:"duration_minutes"`  // optional, defaults from class type
	Capacity        int    `json:"capacity"`          // optional, defaults from class type
	TrainerUserID   *int64 `json:"trainer_user_id"`   // optional
}

// UpdateSessionRequest edits a single materialized session — a substitute
// trainer or a one-off capacity change — without touching the schedule.
// FR-02 §3.1.
type UpdateSessionRequest struct {
	Capacity      *int   `json:"capacity"`
	TrainerUserID *int64 `json:"trainer_user_id"`
}

// SessionResponse is a session with attendance counts, so the booking screen
// can show "6/12 booked" without a second query.
// @Description A class session with current booking counts.
type SessionResponse struct {
	ID              int64     `json:"id"`
	ScheduleID      *int64    `json:"schedule_id,omitempty"`
	ClassTypeID     int64     `json:"class_type_id"`
	ClassTypeName   string    `json:"class_type_name"`
	SessionDate     time.Time `json:"session_date"`
	StartTime       string    `json:"start_time"`
	DurationMinutes int       `json:"duration_minutes"`
	Capacity        int       `json:"capacity"`
	TrainerUserID   *int64    `json:"trainer_user_id,omitempty"`
	TrainerName     *string   `json:"trainer_name,omitempty"`
	Status          string    `json:"status"`
	BookedCount     int       `json:"booked_count"`
	WaitlistCount   int       `json:"waitlist_count"`
}

// ─── Booking ──────────────────────────────────────────────────────────────────

// CreateBookingRequest is the payload for POST /api/v1/class-sessions/{id}/bookings.
// @Description Book a member into a session. Overflow becomes a waitlist entry.
type CreateBookingRequest struct {
	MemberID int64 `json:"member_id"` // required
}

// CancelBookingRequest optionally records why a booking was cancelled.
// @Description Cancel a booking. Frees the slot and promotes the next waitlisted member.
type CancelBookingRequest struct {
	Reason string `json:"reason"` // optional free text, stored alongside the cancel_reason code
}

// MarkAttendanceRequest records whether a member showed up.
// @Description Mark a booking attended or no-show. Only valid after the session's start time.
type MarkAttendanceRequest struct {
	Attended bool `json:"attended"` // true = attended, false = no_show
}

// BookingResponse is a booking with member and session context denormalised.
// @Description A member's booking on a session.
type BookingResponse struct {
	ID               int64      `json:"id"`
	SessionID        int64      `json:"session_id"`
	MemberID         int64      `json:"member_id"`
	MemberName       string     `json:"member_name"`
	Status           string     `json:"status"`
	WaitlistPosition *int       `json:"waitlist_position,omitempty"`
	BookedAt         time.Time  `json:"booked_at"`
	CancelledAt      *time.Time `json:"cancelled_at,omitempty"`
	CancelReason     *string    `json:"cancel_reason,omitempty"`
}

// BookingResult is returned by Book/Cancel/MarkAttendance — the booking that
// was affected, plus the session's fresh counts, so the client can update its
// booked/waitlist tallies without a second round-trip.
// @Description Result of a booking operation.
type BookingResult struct {
	Booking BookingResponse `json:"booking"`
	Session SessionResponse `json:"session"`
	// Promoted is set when cancelling this booking promoted someone off the
	// waitlist — the UI can surface "Rohit was moved off the waitlist."
	Promoted *BookingResponse `json:"promoted,omitempty"`
}
