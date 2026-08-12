package queues

import "time"

// Collections (FR-19 §3) — money the gym is owed and has not collected.
//
// Grouped worst-first, and "worst" is deliberately not "oldest". The group
// that justifies the screen is the one nobody has touched: a due that has
// never been mentioned to anybody is invisible today, exactly as an unattended
// lead was before the workflow existed.
//
// Grouped by member, never by collector. A collections queue with staff names
// and rupee totals against them is one design decision away from a sales
// leaderboard, which FR-13 §1 exists to prevent.

// Activity types on a due.
const (
	ActivityContact  = "contact"
	ActivityPromise  = "promise"
	ActivityWriteOff = "write_off"
)

// Collection group keys.
const (
	GroupUnchased = "unchased"
	GroupChased   = "chased"
	GroupPromised = "promised"
	GroupUpcoming = "upcoming"
)

// CollectionItem is one outstanding due.
type CollectionItem struct {
	PaymentID int64  `json:"payment_id"`
	MemberID  int64  `json:"member_id"`
	Member    string `json:"member"`
	Phone     string `json:"phone,omitempty"`

	AmountInPaise int64      `json:"amount_in_paise"`
	DueDate       *time.Time `json:"due_date,omitempty"`

	// Negative means not yet due. Null when the due carries no date at all,
	// which is its own kind of problem and shown as such rather than assumed
	// to be today.
	DaysOverdue *int `json:"days_overdue,omitempty"`

	// What this member owes in total, across every outstanding due. Shown
	// because chasing ₹1,500 when the same person owes ₹9,000 wastes the call
	// — but see FR-19 §7.2: this is close to a credit score and the gym should
	// confirm they want it.
	MemberTotalInPaise int64 `json:"member_total_in_paise"`

	// The last thing anybody did about it. Nil means nobody has.
	LastContactAt   *time.Time `json:"last_contact_at,omitempty"`
	LastContactBy   *string    `json:"last_contact_by,omitempty"`
	LastContactNote *string    `json:"last_contact_note,omitempty"`
	LastReached     *bool      `json:"last_reached,omitempty"`

	// Set when the member agreed a date and that promise is the newest
	// activity on the due.
	PromisedOn *time.Time `json:"promised_on,omitempty"`

	// True when the member's own membership has already lapsed. Changes the
	// conversation entirely and would otherwise be a nasty surprise mid-call.
	MemberInactive bool `json:"member_inactive"`
}

// CollectionGroup is one band of the queue.
type CollectionGroup struct {
	Key      string `json:"key"`
	Label    string `json:"label"`
	Note     string `json:"note"`
	Severity string `json:"severity"` // urgent | warn | normal

	Items []CollectionItem `json:"items"`

	// Money in this group, so a reader can tell a long tail of small dues from
	// a short list of large ones.
	TotalInPaise int64 `json:"total_in_paise"`
}

// CollectionQueue backs GET /api/v1/queues/collections.
type CollectionQueue struct {
	Groups []CollectionGroup `json:"groups"`

	TotalCount      int   `json:"total_count"`
	TotalInPaise    int64 `json:"total_in_paise"`
	UnchasedCount   int   `json:"unchased_count"`
	MembersInvolved int   `json:"members_involved"`
}
