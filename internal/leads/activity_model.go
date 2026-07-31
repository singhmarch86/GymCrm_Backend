package leads

import "time"

// LeadActivity is one immutable entry in a lead's timeline: a stage
// transition, a logged call, a note, a rescheduled follow-up.
//
// Rows are append-only — never updated or deleted. That is what makes
// time-in-stage analytics possible: the leads table stores only the *current*
// status, so without this history every transition would be lost.
type LeadActivity struct {
	ID     int64 `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID  int64 `gorm:"not null"                 json:"gym_id"`
	LeadID int64 `gorm:"not null"                 json:"lead_id"`

	// Nullable — system-generated entries have no acting user.
	UserID *int64 `gorm:"" json:"user_id,omitempty"`
	// Resolved via JOIN, never written. `->` (read-only) rather than `-`,
	// which would make GORM skip the field on reads too and leave it empty.
	UserName string `gorm:"->" json:"user_name,omitempty"`

	Type ActivityType `gorm:"type:varchar(30);not null" json:"type"`
	Note *string      `gorm:"type:text"                 json:"note,omitempty"`

	// Set only for Type == ActivityStageChange.
	FromStatus *string `gorm:"type:varchar(30)" json:"from_status,omitempty"`
	ToStatus   *string `gorm:"type:varchar(30)" json:"to_status,omitempty"`

	CreatedAt time.Time `gorm:"autoCreateTime" json:"created_at"`
}

func (LeadActivity) TableName() string { return "lead_activities" }

type ActivityType string

const (
	ActivityCreated        ActivityType = "created"
	ActivityStageChange    ActivityType = "stage_change"
	ActivityCall           ActivityType = "call"
	ActivityNote           ActivityType = "note"
	ActivityFollowUpSet    ActivityType = "follow_up_set"
	ActivityTrialScheduled ActivityType = "trial_scheduled"
	ActivityConverted      ActivityType = "converted"
	ActivityLost           ActivityType = "lost"
)

// IsValidActivityType reports whether s is a type a client may submit.
// Stage transitions, creation and conversion are logged by the server itself,
// so they are deliberately excluded — a client cannot fake pipeline history.
func IsValidActivityType(s string) bool {
	switch ActivityType(s) {
	case ActivityCall, ActivityNote, ActivityFollowUpSet, ActivityTrialScheduled:
		return true
	}
	return false
}
