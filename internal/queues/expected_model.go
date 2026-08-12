package queues

import "time"

// Expected payments (FR-19 §5) — money the gym has reason to think is coming
// in over a chosen span of days.
//
// Two sources, kept apart on purpose and never added into one figure:
//
//   - Raised. A due already written down, with a due date in the span. The
//     gym decided this was owed; the only question is whether it arrives.
//   - Expiring. A membership whose expiry falls in the span, valued at the
//     plan's price today. Nobody has agreed to pay this. The member may
//     renew, downgrade, or walk.
//
// A single "expected" total would be a forecast wearing a ledger's clothes,
// and on live data the estimate is roughly thirteen times the raised amount —
// blend them and the raised number disappears inside a guess. The screen shows
// both and says which is which.
//
// Nothing here is a prediction of renewal *rate*. This is the ceiling: what
// arrives if every expiring member renews at the same price, which they will
// not. That reading is stated on the response so a client cannot present it as
// a forecast without contradicting the payload.
const (
	KindRaised   = "raised"
	KindExpiring = "expiring"
)

// ExpectedItemLimit caps the listed rows. A month holds 300+ expiries and no
// desk works a list that long from the top; the totals stay exact regardless,
// because they are summed in SQL rather than from the rows returned.
const ExpectedItemLimit = 200

// ExpectedItem is one thing the gym expects money from.
type ExpectedItem struct {
	Kind string `json:"kind"`

	MemberID int64  `json:"member_id"`
	Member   string `json:"member"`
	Phone    string `json:"phone,omitempty"`

	// For a raised due this is what is owed. For an expiring membership it is
	// the plan's current price, and [Estimated] is true.
	AmountInPaise int64 `json:"amount_in_paise"`
	Estimated     bool  `json:"estimated"`

	// Due date for a raised due, expiry date for a membership.
	Date *time.Time `json:"date,omitempty"`

	// Raised dues only, so the row can be acted on in the Collect queue.
	PaymentID *int64 `json:"payment_id,omitempty"`

	// Expiring memberships only.
	PlanName    *string    `json:"plan_name,omitempty"`
	LastVisitAt *time.Time `json:"last_visit_at,omitempty"`

	// What this member already owes, whatever the row is about. Expecting a
	// renewal from somebody sitting on an unpaid due is a different
	// conversation, and it should not be a surprise mid-call.
	OwedInPaise int64 `json:"owed_in_paise"`
}

// ExpectedBucket is one column of the shape of the span: a day when the span
// is short enough to read day by day, a month when it is not.
//
// The two figures stay separate here too. A stacked total per day would
// re-blend exactly what the split above exists to keep apart.
type ExpectedBucket struct {
	Key   string `json:"key"`
	Label string `json:"label"`

	RaisedInPaise   int64 `json:"raised_in_paise"`
	ExpiringInPaise int64 `json:"expiring_in_paise"`

	RaisedCount   int `json:"raised_count"`
	ExpiringCount int `json:"expiring_count"`
}

// ExpectedPayments backs GET /api/v1/queues/expected.
type ExpectedPayments struct {
	From        string `json:"from"`
	To          string `json:"to"`
	Days        int    `json:"days"`
	IsSingleDay bool   `json:"is_single_day"`

	// Exact, summed in SQL over the whole span rather than over the rows
	// returned — so truncating the list never moves a total.
	RaisedCount   int   `json:"raised_count"`
	RaisedInPaise int64 `json:"raised_in_paise"`

	ExpiringCount   int   `json:"expiring_count"`
	ExpiringInPaise int64 `json:"expiring_in_paise"`

	// Bucketed by day or by month, whichever the span can be read as.
	BucketUnit string           `json:"bucket_unit"`
	Buckets    []ExpectedBucket `json:"buckets"`

	Items     []ExpectedItem `json:"items"`
	Truncated bool           `json:"truncated"`
}

// BucketByMonth is the span length past which per-day columns stop being
// legible. Roughly a long month.
const BucketByMonth = 31
