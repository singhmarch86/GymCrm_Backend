package queues

import "time"

// Renewals due (FR-19 §4) — money the gym is about to be owed.
//
// This is what "expected payments" actually is. Nothing is ever scheduled
// forward into the payments table, so the only forward-looking signal is a
// membership expiry date.
//
// Windowed at 30 days either side by decision, not by accident. Without a cap
// the already-lapsed tail is 88 people going back months, and a permanently
// red pile that large is wallpaper by the second week. The count outside the
// window is still reported — capped is not the same as hidden, and a queue
// that quietly drops people is worse than one that admits its own edge.
const RenewalWindowDays = 30

// Renewal group keys.
const (
	GroupLapsed   = "lapsed"
	GroupDueToday = "due_today"
	GroupDueWeek  = "due_week"
	GroupDueMonth = "due_month"
)

// RenewalItem is one membership approaching or past its expiry.
type RenewalItem struct {
	MemberID int64  `json:"member_id"`
	Member   string `json:"member"`
	Phone    string `json:"phone,omitempty"`

	PlanID      *int64  `json:"plan_id,omitempty"`
	PlanName    *string `json:"plan_name,omitempty"`
	PlanInPaise *int64  `json:"plan_in_paise,omitempty"`

	ExpiryDate *time.Time `json:"expiry_date,omitempty"`

	// Negative means it has already passed. The queue reads this rather than
	// recomputing from the date, so the grouping and the label can never
	// disagree.
	DaysUntilExpiry int `json:"days_until_expiry"`

	// When they last came in. A member who stopped attending three weeks
	// before their expiry is a different conversation from one who trained
	// yesterday, and the call goes better for knowing which.
	LastVisitAt *time.Time `json:"last_visit_at,omitempty"`

	// Outstanding money on the same member. Renewing somebody who already owes
	// is a decision, not an oversight, so it is said up front.
	OwedInPaise int64 `json:"owed_in_paise"`

	// How many times they have renewed before. A first-timer lapsing is very
	// different from somebody on their fifth renewal.
	PreviousRenewals int `json:"previous_renewals"`
}

// RenewalGroup is one band of the queue.
type RenewalGroup struct {
	Key      string `json:"key"`
	Label    string `json:"label"`
	Note     string `json:"note"`
	Severity string `json:"severity"`

	Items []RenewalItem `json:"items"`

	// What renewing this whole group would be worth, at current plan prices.
	// An estimate and labelled as one — the member may change plan.
	ValueInPaise int64 `json:"value_in_paise"`
}

// RenewalQueue backs GET /api/v1/queues/renewals.
type RenewalQueue struct {
	Groups []RenewalGroup `json:"groups"`

	WindowDays int `json:"window_days"`

	TotalCount   int   `json:"total_count"`
	ValueInPaise int64 `json:"value_in_paise"`

	// Lapsed longer ago than the window. Not listed, but never silently
	// dropped: the reader is told the number and where those people went.
	BeyondWindow int `json:"beyond_window"`
}
