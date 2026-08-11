package leads

import "time"

// The lead workflow (FR-18).
//
// The invariant this file exists to hold: every open lead has exactly one next
// step, owned by one person, with a date. A lead missing any of the three is
// Unattended — the state that today is invisible, and the reason leads die
// without ever appearing overdue.

// NextStep is what somebody is going to do about this lead.
//
// Values are validated here rather than by a CHECK constraint: FR-18 §2's
// defaults are expected to be corrected by the pilot gym once they have
// watched a real week, and that should not require a migration.
type NextStep string

const (
	StepFirstContact NextStep = "first_contact"
	StepCallBack     NextStep = "call_back"
	StepBookTrial    NextStep = "book_trial"
	StepConfirmTrial NextStep = "confirm_trial"
	StepCounselling  NextStep = "counselling"
	StepClose        NextStep = "close"
	StepFixNumber    NextStep = "fix_number"
)

var AllNextSteps = []NextStep{
	StepFirstContact,
	StepCallBack,
	StepBookTrial,
	StepConfirmTrial,
	StepCounselling,
	StepClose,
	StepFixNumber,
}

// Label is what the staff member reads. Phrased as an instruction, not a noun:
// "Book a trial" is something you can do, "Trial booking" is a category.
func (s NextStep) Label() string {
	switch s {
	case StepFirstContact:
		return "Make first contact"
	case StepCallBack:
		return "Call back"
	case StepBookTrial:
		return "Book a trial"
	case StepConfirmTrial:
		return "Confirm they are coming"
	case StepCounselling:
		return "Counselling — discuss plans"
	case StepClose:
		return "Close, or record why not"
	case StepFixNumber:
		return "Get a working number"
	}
	return string(s)
}

func IsValidNextStep(s string) bool {
	for _, x := range AllNextSteps {
		if NextStep(s) == x {
			return true
		}
	}
	return false
}

// DefaultStepFor returns the step a lead should carry on arriving at a stage,
// and how many days from today it is due (FR-18 §2).
//
// ok is false for joined and lost: those clear the step entirely (FR-18 §6).
// Nothing should nag about a member who already joined — that is how staff
// learn to ignore the queue.
//
// These are defaults, not rules. Staff override any of them, and the pilot gym
// is expected to correct the day counts, which were reasoned from how gym
// sales usually run rather than from watching this gym.
func DefaultStepFor(status LeadStatus) (step NextStep, dueInDays int, ok bool) {
	switch status {
	case LeadStatusNew:
		return StepFirstContact, 0, true // same day: a cold lead is a perishable
	case LeadStatusContacted:
		return StepBookTrial, 2, true
	case LeadStatusTrialScheduled:
		// Overridden by the caller to the day before trial_date when one is
		// set — a confirmation call is worthless after the trial has passed.
		return StepConfirmTrial, 1, true
	case LeadStatusTrialCompleted:
		return StepCounselling, 1, true
	}
	return "", 0, false
}

// Suggestion is what the UI offers after an outcome is logged: pre-filled,
// one tap, and declinable.
type Suggestion struct {
	Step NextStep  `json:"step"`
	Due  time.Time `json:"due"`
	// Why this is being offered, shown to the staff member. A suggestion that
	// cannot explain itself gets accepted without thought, which is the same
	// as automating it.
	Reason string `json:"reason"`
}

// SuggestNext maps a logged call outcome to the step that usually follows
// (FR-18 §3).
//
// It *suggests*. Nothing here writes. A workflow that reschedules itself stops
// meaning "somebody decided this" and starts meaning "the computer guessed" —
// and dates nobody chose are dates nobody honours.
//
// callBackDate is what the member asked for, when they asked for something.
func SuggestNext(
	outcome ActivityOutcome, today time.Time, callBackDate *time.Time,
) (Suggestion, bool) {
	day := func(n int) time.Time { return today.AddDate(0, 0, n) }

	switch outcome {
	case OutcomeNoAnswer:
		// Tomorrow, not today: calling twice in an hour is how a gym becomes
		// the number somebody stops answering.
		return Suggestion{StepCallBack, day(1), "No answer — try again tomorrow"}, true

	case OutcomeCallBack:
		// Their date wins over any default. This is the one case where the
		// member has already told us the answer.
		due := day(2)
		reason := "They asked to be called back"
		if callBackDate != nil {
			due = *callBackDate
			reason = "The day they asked for"
		}
		return Suggestion{StepCallBack, due, reason}, true

	case OutcomeAnswered, OutcomeInterested:
		return Suggestion{StepBookTrial, day(1), "They are engaged — get them in"}, true

	case OutcomeNotInterested:
		// Suggests closing; does not close. FR-16 §4 — logging an outcome
		// never changes the lead's status by itself.
		return Suggestion{StepClose, day(0), "Record why, so the loss counts for something"}, true

	case OutcomeWrongNumber:
		return Suggestion{StepFixNumber, day(0), "No working number — nothing else can happen"}, true
	}

	return Suggestion{}, false
}

// WorkflowState is why a lead appears in the queue. Ordered by urgency, and
// Unattended sits above overdue on purpose: a lead nobody has picked up is a
// worse failure than one being chased late.
type WorkflowState string

const (
	StateUnattended WorkflowState = "unattended"
	StateOverdue    WorkflowState = "overdue"
	StateToday      WorkflowState = "today"
	StateUpcoming   WorkflowState = "upcoming"
	StateClosed     WorkflowState = "closed"
)

func (w WorkflowState) Label() string {
	switch w {
	case StateUnattended:
		return "Nobody is on these"
	case StateOverdue:
		return "Overdue"
	case StateToday:
		return "Due today"
	case StateUpcoming:
		return "Coming up"
	case StateClosed:
		return "Closed"
	}
	return string(w)
}

// StateOf classifies one lead. today must already be in the gym's timezone.
func StateOf(l *Lead, today time.Time) WorkflowState {
	if l.Status == LeadStatusJoined || l.Status == LeadStatusLost {
		return StateClosed
	}
	// All three parts of the invariant are required. A step with no date is as
	// unattended as no step at all — nobody will ever be reminded of it.
	if l.NextStep == nil || *l.NextStep == "" ||
		l.NextStepDue == nil || l.AssignedUserID == nil {
		return StateUnattended
	}

	due := l.NextStepDue.In(today.Location())
	d := time.Date(due.Year(), due.Month(), due.Day(), 0, 0, 0, 0, today.Location())
	t := time.Date(today.Year(), today.Month(), today.Day(), 0, 0, 0, 0, today.Location())

	switch {
	case d.Before(t):
		return StateOverdue
	case d.Equal(t):
		return StateToday
	default:
		return StateUpcoming
	}
}
