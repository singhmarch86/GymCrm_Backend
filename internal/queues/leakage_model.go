package queues

import "time"

// Money leakage (FR-21) — value the gym gave away without meaning to.
//
// The collections queue answers "who owes us money we billed". This answers
// the harder question: "what did we hand over and never bill at all". Those
// leaks never appear in a debtors list, because nobody ever wrote the debt
// down — which is exactly why they persist.
//
// Every check here is a *finding*, not an accusation. A member training past
// their expiry might have renewed in cash that somebody forgot to enter; a
// session past the package limit might be a goodwill session the owner
// approved. The queue says what it saw and what it is worth, and a human
// decides. Nothing here auto-charges anybody.

// Leak kinds.
const (
	// Sessions delivered beyond what the package paid for. Exact: a count of
	// appointments against a number of sessions bought.
	LeakOversoldPT = "oversold_pt"

	// The package's own counter disagrees with its appointments. Not money on
	// its own, but it is how an oversold package hides — the counter stops at
	// the limit while sessions keep being booked.
	LeakSessionDrift = "session_drift"

	// Attendance after the membership expired, with no renewal covering it.
	// The classic gym leak: the door keeps opening because nobody told the
	// desk to stop.
	LeakTrainingExpired = "training_expired"
)

// LeakItem is one finding.
type LeakItem struct {
	Kind string `json:"kind"`

	MemberID int64  `json:"member_id"`
	Member   string `json:"member"`
	Phone    string `json:"phone,omitempty"`

	TrainerID *int64  `json:"trainer_id,omitempty"`
	Trainer   *string `json:"trainer,omitempty"`

	// What the finding is about, in the reader's words.
	Detail string `json:"detail"`

	// What it is worth, where that can be said honestly. Zero when the value
	// cannot be derived — a drifted counter costs nothing by itself, and
	// inventing a number for it would make the total meaningless.
	ValueInPaise int64 `json:"value_in_paise"`

	// How the value was arrived at. Shown next to the figure, because a
	// number nobody can reconstruct is a number nobody will act on.
	Basis string `json:"basis,omitempty"`

	// The count behind the finding: sessions over, visits after expiry.
	Count int `json:"count"`

	// When it started going wrong, where that is knowable.
	Since *time.Time `json:"since,omitempty"`

	PackageID *int64 `json:"package_id,omitempty"`
}

// LeakGroup is one kind of leak.
type LeakGroup struct {
	Kind  string `json:"kind"`
	Label string `json:"label"`

	// What this check looks for and what it cannot see. Rendered above the
	// rows: a finding the reader cannot interpret is one they will ignore.
	Note string `json:"note"`

	Severity string `json:"severity"`

	Items        []LeakItem `json:"items"`
	ValueInPaise int64      `json:"value_in_paise"`
}

// LeakageReport backs GET /api/v1/queues/leakage.
type LeakageReport struct {
	Groups []LeakGroup `json:"groups"`

	TotalCount int `json:"total_count"`

	// Only the leaks that could be valued honestly. Said as such on screen —
	// this is the floor of what leaked, never the whole of it.
	ValuedInPaise int64 `json:"valued_in_paise"`

	// Findings that are real but carry no rupee figure.
	UnvaluedCount int `json:"unvalued_count"`
}

func (r LeakageReport) IsClear() bool { return r.TotalCount == 0 }
