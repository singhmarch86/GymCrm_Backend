package leads

import (
	"time"

	"gorm.io/gorm"
)

// Lead is a prospective member moving through a 6-stage sales pipeline.
// Soft-deleted (DeletedAt) — historical lead data is preserved.
type Lead struct {
	ID    int64 `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID int64 `gorm:"not null"                 json:"gym_id"`

	// Basic info
	Name   string  `gorm:"type:varchar(200);not null" json:"name"`
	Phone  string  `gorm:"type:varchar(20);not null"  json:"phone"`
	Email  *string `gorm:"type:varchar(200)"          json:"email,omitempty"`
	Gender *string `gorm:"type:varchar(10)"           json:"gender,omitempty"`

	// Lead context
	Source LeadSource `gorm:"type:varchar(50);not null;default:'walk_in'" json:"source"`
	Goal   *LeadGoal  `gorm:"type:varchar(50)"           json:"goal,omitempty"`
	Notes  *string    `gorm:"type:text"                  json:"notes,omitempty"`

	// Pipeline
	Status LeadStatus `gorm:"type:varchar(30);not null;default:'new_lead'" json:"status"`

	// Key dates
	TrialDate    *time.Time `gorm:"type:date"                  json:"trial_date,omitempty"`
	FollowUpDate *time.Time `gorm:"type:date"                  json:"follow_up_date,omitempty"`

	// The workflow (FR-18). Deliberately separate from FollowUpDate: that
	// answers "when do I contact them again", these answer "what am I doing
	// and why". A lead can have a trial next Tuesday and a confirmation call
	// on Monday; one column loses the second every time.
	//
	// Nil is meaningful — it puts the lead in Unattended, which is the state
	// this whole feature exists to make visible.
	NextStep    *string    `gorm:"type:varchar(40)" json:"next_step,omitempty"`
	NextStepDue *time.Time `gorm:"type:date"        json:"next_step_due,omitempty"`
	LostReason  *string    `gorm:"type:text"                  json:"lost_reason,omitempty"`

	// Assignment
	AssignedUserID *int64 `gorm:""                           json:"assigned_user_id,omitempty"`
	// Resolved via JOIN, never written. Must be `->` (read-only) and NOT `-`:
	// `-` makes GORM ignore the field on reads as well, so the joined alias
	// silently never populates and the name comes back empty.
	AssignedUserName string `gorm:"->"                         json:"assigned_user_name,omitempty"`

	// Future conversion hook
	ConvertedMemberID *int64 `gorm:""                           json:"converted_member_id,omitempty"`

	CreatedAt time.Time      `gorm:"autoCreateTime"             json:"created_at"`
	UpdatedAt time.Time      `gorm:"autoUpdateTime"             json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index"                      json:"-"`
}

func (Lead) TableName() string { return "leads" }

// ─── Enums ────────────────────────────────────────────────────────────────────

type LeadStatus string

const (
	LeadStatusNew            LeadStatus = "new_lead"
	LeadStatusContacted      LeadStatus = "contacted"
	LeadStatusTrialScheduled LeadStatus = "trial_scheduled"
	LeadStatusTrialCompleted LeadStatus = "trial_completed"
	LeadStatusJoined         LeadStatus = "joined"
	LeadStatusLost           LeadStatus = "lost"
)

// PipelineOrder defines the display/progression order of statuses.
var PipelineOrder = []LeadStatus{
	LeadStatusNew,
	LeadStatusContacted,
	LeadStatusTrialScheduled,
	LeadStatusTrialCompleted,
	LeadStatusJoined,
	LeadStatusLost,
}

type LeadSource string

const (
	LeadSourceWalkIn    LeadSource = "walk_in"
	LeadSourceReferral  LeadSource = "referral"
	LeadSourceInstagram LeadSource = "instagram"
	LeadSourceFacebook  LeadSource = "facebook"
	LeadSourceGoogle    LeadSource = "google"
	LeadSourceWhatsApp  LeadSource = "whatsapp"
	LeadSourceWebsite   LeadSource = "website"
	LeadSourceOther     LeadSource = "other"
)

type LeadGoal string

const (
	LeadGoalWeightLoss     LeadGoal = "weight_loss"
	LeadGoalMuscleGain     LeadGoal = "muscle_gain"
	LeadGoalFitness        LeadGoal = "fitness"
	LeadGoalSports         LeadGoal = "sports"
	LeadGoalRehabilitation LeadGoal = "rehabilitation"
	LeadGoalOther          LeadGoal = "other"
)

// IsValidStatus checks if the given status is a valid LeadStatus.
func IsValidStatus(s string) bool {
	for _, v := range PipelineOrder {
		if LeadStatus(s) == v {
			return true
		}
	}
	return false
}

// IsValidSource checks if the given source is a valid LeadSource.
func IsValidSource(s string) bool {
	switch LeadSource(s) {
	case LeadSourceWalkIn, LeadSourceReferral, LeadSourceInstagram,
		LeadSourceFacebook, LeadSourceGoogle, LeadSourceWhatsApp,
		LeadSourceWebsite, LeadSourceOther:
		return true
	}
	return false
}
