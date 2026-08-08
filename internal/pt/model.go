package pt

import "time"

const (
	PackageActive    = "active"
	PackageExpired   = "expired"
	PackageCancelled = "cancelled"
)

const (
	AppointmentScheduled = "scheduled"
	AppointmentCompleted = "completed"
	AppointmentCancelled = "cancelled"
	AppointmentNoShow    = "no_show"
)

// Package is a sold PT package — a session-credit counter, not a catalog
// entry. sessions_used only increments when an Appointment against it is
// completed. See docs/FR-03-trainers-pt-appointments.md §2.
type Package struct {
	ID        int64 `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID     int64 `gorm:"not null"                 json:"gym_id"`
	MemberID  int64 `gorm:"not null"                 json:"member_id"`
	TrainerID int64 `gorm:"not null"                 json:"trainer_id"`

	PackageName    string `gorm:"not null" json:"package_name"`
	TotalSessions  int    `gorm:"not null" json:"total_sessions"`
	SessionsUsed   int    `gorm:"not null;default:0" json:"sessions_used"`
	AmountInPaise  int64  `gorm:"not null" json:"amount_in_paise"`
	ExpiryDate     *time.Time `gorm:"type:date" json:"expiry_date,omitempty"`

	Status string `gorm:"type:varchar(20);not null;default:'active'" json:"status"`

	CreatedAt time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt time.Time `gorm:"autoUpdateTime" json:"updated_at"`
}

func (Package) TableName() string { return "pt_packages" }

func (p Package) sessionsRemaining() int { return p.TotalSessions - p.SessionsUsed }

// Appointment is a 1:1 trainer/member booking. Booking never checks or
// reserves a credit; completing one does, and fails if the package is
// exhausted. See FR-03 §3.
type Appointment struct {
	ID           int64 `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID        int64 `gorm:"not null"                 json:"gym_id"`
	PTPackageID  int64 `gorm:"not null"                 json:"pt_package_id"`
	TrainerID    int64 `gorm:"not null"                 json:"trainer_id"`
	MemberID     int64 `gorm:"not null"                 json:"member_id"`

	ScheduledAt     time.Time `gorm:"not null" json:"scheduled_at"`
	DurationMinutes int       `gorm:"not null;default:60" json:"duration_minutes"`
	Status          string    `gorm:"type:varchar(20);not null;default:'scheduled'" json:"status"`
	Notes           *string   `json:"notes,omitempty"`

	CreatedByUserID int64     `gorm:"not null" json:"created_by_user_id"`
	CreatedAt       time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt       time.Time `gorm:"autoUpdateTime" json:"updated_at"`
}

func (Appointment) TableName() string { return "pt_appointments" }
