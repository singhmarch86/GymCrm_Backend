package ptfeedback

import "time"

// Feedback, staff-transcribed either way.
//
// Trainers have no login (FR-03: users.role is only owner/staff) and there is
// no member-facing app, so "the member said" and "the trainer observed" are
// both written by whoever is at the desk. One table, one AuthorRole field,
// rather than two features that would otherwise be identical in shape.
const (
	AuthorMember  = "member"
	AuthorTrainer = "trainer"
)

type Feedback struct {
	ID       int64 `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID    int64 `gorm:"not null"                 json:"gym_id"`
	MemberID int64 `gorm:"not null"                 json:"member_id"`

	AuthorRole string `gorm:"type:varchar(20);not null" json:"author_role"`

	// All three independent and optional — a note can carry none, either, or
	// all three. See migration 035 for why.
	TrainerID       *int64 `json:"trainer_id,omitempty"`
	PTPackageID     *int64 `json:"pt_package_id,omitempty"`
	PTAppointmentID *int64 `json:"pt_appointment_id,omitempty"`

	Note string `gorm:"type:text;not null" json:"note"`

	CreatedByUserID int64     `gorm:"not null" json:"created_by_user_id"`
	CreatedAt       time.Time `gorm:"autoCreateTime" json:"created_at"`
}

func (Feedback) TableName() string { return "member_feedback" }

// Row is a feedback entry as a list screen shows it: names rather than bare
// ids, so the client never has to join member/trainer names itself.
type Row struct {
	ID              int64     `json:"id"`
	MemberID        int64     `json:"member_id"`
	MemberName      string    `json:"member_name"`
	AuthorRole      string    `json:"author_role"`
	TrainerID       *int64    `json:"trainer_id,omitempty"`
	TrainerName     *string   `json:"trainer_name,omitempty"`
	PTPackageID     *int64    `json:"pt_package_id,omitempty"`
	PTAppointmentID *int64    `json:"pt_appointment_id,omitempty"`
	Note            string    `json:"note"`
	CreatedByName   string    `json:"created_by_name"`
	CreatedAt       time.Time `json:"created_at"`
}
