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

	// What came of it (FR-16). Nil is a real answer, not a missing one: a note
	// has no outcome, and every row written before this column existed has
	// none. Never inferred — see FR-16 §3.
	Outcome *ActivityOutcome `gorm:"type:varchar(30)" json:"outcome,omitempty"`

	// Set only for Type == ActivityStageChange.
	FromStatus *string `gorm:"type:varchar(30)" json:"from_status,omitempty"`
	ToStatus   *string `gorm:"type:varchar(30)" json:"to_status,omitempty"`

	CreatedAt time.Time `gorm:"autoCreateTime" json:"created_at"`
}

func (LeadActivity) TableName() string { return "lead_activities" }

type ActivityType string

const (
	ActivityCreated     ActivityType = "created"
	ActivityStageChange ActivityType = "stage_change"
	ActivityCall        ActivityType = "call"
	ActivityNote        ActivityType = "note"
	// The sit-down after a trial where plans and price get discussed — the
	// highest-conversion moment in the pipeline, and until FR-18 it was
	// indistinguishable from a note, so nobody could count whether it was
	// happening at all.
	ActivityCounselling    ActivityType = "counselling"
	ActivityFollowUpSet    ActivityType = "follow_up_set"
	ActivityTrialScheduled ActivityType = "trial_scheduled"
	ActivityConverted      ActivityType = "converted"
	ActivityLost           ActivityType = "lost"
)

// ActivityOutcome is what came of a follow-up (FR-16).
//
// Six values, and the count is the point: a desk facing fifteen options picks
// the first plausible one and the data becomes noise that looks like signal.
// Adding a seventh should mean deleting one.
type ActivityOutcome string

const (
	OutcomeAnswered      ActivityOutcome = "answered"
	OutcomeNoAnswer      ActivityOutcome = "no_answer"
	OutcomeCallBack      ActivityOutcome = "call_back"
	OutcomeInterested    ActivityOutcome = "interested"
	OutcomeNotInterested ActivityOutcome = "not_interested"
	OutcomeWrongNumber   ActivityOutcome = "wrong_number"
)

// AllOutcomes is the display order: reached, not reached, then the verdicts.
var AllOutcomes = []ActivityOutcome{
	OutcomeAnswered,
	OutcomeNoAnswer,
	OutcomeCallBack,
	OutcomeInterested,
	OutcomeNotInterested,
	OutcomeWrongNumber,
}

// Label is what the desk should read, in their words.
func (o ActivityOutcome) Label() string {
	switch o {
	case OutcomeAnswered:
		return "Answered"
	case OutcomeNoAnswer:
		return "No answer"
	case OutcomeCallBack:
		return "Call back later"
	case OutcomeInterested:
		return "Interested"
	case OutcomeNotInterested:
		return "Not interested"
	case OutcomeWrongNumber:
		return "Wrong number"
	}
	return string(o)
}

// IsValidOutcome reports whether s is one of the six.
func IsValidOutcome(s string) bool {
	for _, o := range AllOutcomes {
		if ActivityOutcome(s) == o {
			return true
		}
	}
	return false
}

// AcceptsOutcome reports whether an outcome may be attached to this type.
//
// Server-written history is excluded (FR-16 §7): a client able to tag a
// stage_change with an outcome could rewrite what the funnel analytics report.
func (t ActivityType) AcceptsOutcome() bool {
	return IsValidActivityType(string(t))
}

// IsValidActivityType reports whether s is a type a client may submit.
// Stage transitions, creation and conversion are logged by the server itself,
// so they are deliberately excluded — a client cannot fake pipeline history.
func IsValidActivityType(s string) bool {
	switch ActivityType(s) {
	case ActivityCall, ActivityNote, ActivityCounselling,
		ActivityFollowUpSet, ActivityTrialScheduled:
		return true
	}
	return false
}
