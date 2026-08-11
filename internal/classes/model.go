package classes

import "time"

// Session status. Mirrors chk_class_sessions_status in migration 013.
const (
	SessionScheduled = "scheduled"
	SessionCancelled = "cancelled"
	SessionCompleted = "completed"
)

// Booking status. Mirrors chk_bookings_status in migration 013.
const (
	BookingBooked     = "booked"
	BookingWaitlisted = "waitlisted"
	BookingCancelled  = "cancelled"
	BookingAttended   = "attended"
	BookingNoShow     = "no_show"
)

// Cancellation reasons — free text elsewhere, constrained here because these
// three drive reporting and (later) notification routing. FR-02 §3.3, §4.2.
const (
	CancelReasonMember           = "member"
	CancelReasonLate             = "late"
	CancelReasonSessionCancelled = "session_cancelled"
)

// Policy constants — see docs/FR-02-classes-booking.md.
const (
	GenerationWindowDays  = 30 // FR-02 §2 — how far ahead sessions are materialized
	CancellationWindowHrs = 2  // FR-02 §4.2 — cancelling inside this window is "late"
)

// ClassType is the offering — "Yoga", "Zumba". Long-lived, edited rarely.
type ClassType struct {
	ID              int64      `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID           int64      `gorm:"not null"                 json:"gym_id"`
	Name            string     `gorm:"not null"                 json:"name"`
	Description     *string    `json:"description,omitempty"`
	DurationMinutes int        `gorm:"not null"                 json:"duration_minutes"`
	DefaultCapacity int        `gorm:"not null"                 json:"default_capacity"`
	IsActive        bool       `gorm:"not null;default:true"    json:"is_active"`
	CreatedAt       time.Time  `gorm:"autoCreateTime"           json:"created_at"`
	UpdatedAt       time.Time  `gorm:"autoUpdateTime"           json:"updated_at"`
	DeletedAt       *time.Time `json:"-"`
}

func (ClassType) TableName() string { return "class_types" }

// ClassSchedule is the recurrence rule: day/time/trainer/capacity, with an
// effective date range. Editing this never retroactively changes sessions
// already materialized — see FR-02 §0.1, §2.
type ClassSchedule struct {
	ID          int64 `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID       int64 `gorm:"not null"                 json:"gym_id"`
	ClassTypeID int64 `gorm:"not null"                 json:"class_type_id"`

	DayOfWeek       int    `gorm:"not null"                 json:"day_of_week"` // 0=Sunday..6=Saturday
	StartTime       string `gorm:"type:time;not null"       json:"start_time"`  // "HH:MM:SS"
	DurationMinutes int    `gorm:"not null"                 json:"duration_minutes"`
	Capacity        int    `gorm:"not null"                 json:"capacity"`
	TrainerUserID   *int64 `json:"trainer_user_id,omitempty"` // nullable — FR-02 §0.2

	EffectiveFrom  time.Time  `gorm:"type:date;not null"       json:"effective_from"`
	EffectiveUntil *time.Time `gorm:"type:date"                json:"effective_until,omitempty"`

	IsActive  bool       `gorm:"not null;default:true"    json:"is_active"`
	CreatedAt time.Time  `gorm:"autoCreateTime"           json:"created_at"`
	UpdatedAt time.Time  `gorm:"autoUpdateTime"           json:"updated_at"`
	DeletedAt *time.Time `json:"-"`
}

func (ClassSchedule) TableName() string { return "class_schedules" }

// ClassSession is one bookable occurrence. Capacity/trainer/duration are a
// SNAPSHOT copied from the schedule at generation time — never a live
// reference. This is what makes a substitute trainer or one-off capacity
// change possible without disturbing the recurrence rule or any other
// session. FR-02 §3.1.
type ClassSession struct {
	ID          int64  `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID       int64  `gorm:"not null"                 json:"gym_id"`
	ScheduleID  *int64 `json:"schedule_id,omitempty"` // nullable — ad-hoc sessions allowed
	ClassTypeID int64  `gorm:"not null"                 json:"class_type_id"`

	SessionDate     time.Time `gorm:"type:date;not null"       json:"session_date"`
	StartTime       string    `gorm:"type:time;not null"       json:"start_time"`
	DurationMinutes int       `gorm:"not null"                 json:"duration_minutes"`
	Capacity        int       `gorm:"not null"                 json:"capacity"`
	TrainerUserID   *int64    `json:"trainer_user_id,omitempty"`

	Status string `gorm:"type:varchar(20);not null;default:'scheduled'" json:"status"`

	CreatedAt time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt time.Time `gorm:"autoUpdateTime" json:"updated_at"`
}

func (ClassSession) TableName() string { return "class_sessions" }

// startsAt combines session_date and start_time into a single instant, used
// to reject booking a session that has already started (FR-02 §4.1) and to
// compute the cancellation window (FR-02 §4.2).
func (s ClassSession) startsAt() (time.Time, error) {
	t, err := time.Parse("15:04:05", s.StartTime)
	if err != nil {
		return time.Time{}, err
	}
	return time.Date(
		s.SessionDate.Year(), s.SessionDate.Month(), s.SessionDate.Day(),
		t.Hour(), t.Minute(), t.Second(), 0, time.UTC,
	), nil
}

// Booking is one member's claim on one session.
type Booking struct {
	ID        int64 `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID     int64 `gorm:"not null"                 json:"gym_id"`
	SessionID int64 `gorm:"not null"                 json:"session_id"`
	MemberID  int64 `gorm:"not null"                 json:"member_id"`

	Status           string `gorm:"type:varchar(20);not null;default:'booked'" json:"status"`
	WaitlistPosition *int   `json:"waitlist_position,omitempty"`

	BookedAt     time.Time  `gorm:"autoCreateTime" json:"booked_at"`
	CancelledAt  *time.Time `json:"cancelled_at,omitempty"`
	CancelReason *string    `gorm:"type:varchar(30)" json:"cancel_reason,omitempty"`

	CreatedAt time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt time.Time `gorm:"autoUpdateTime" json:"updated_at"`
}

func (Booking) TableName() string { return "bookings" }

func (b Booking) isActive() bool {
	return b.Status == BookingBooked || b.Status == BookingWaitlisted
}
