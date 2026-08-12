package staffwork

// Staff work analytics (FR-22).
//
// This is the screen FR-13 §1 was written to guard against, so the shape is
// constrained deliberately and the constraints are the design:
//
//   - Nobody is ranked. People come back ordered by name, there is no score,
//     no rating and no "top performer" field for a client to sort on.
//   - A person is only ever compared to THEMSELVES. "Simran logged a third
//     fewer calls than last month" is a question worth asking her. "Simran
//     logged fewer calls than Rajeev" is a claim about two people doing
//     different jobs on different shifts, and the data cannot support it.
//   - Nothing is coloured for being low. A drop is shown as a number and left
//     for a human to interpret, because the honest explanations — annual
//     leave, a fortnight on the front desk instead of the phone, a quiet
//     January — are invisible to this query.
//
// What the screen is actually for is the gym: is the desk busier than it was,
// which ledgers carry the work, and which days nobody recorded anything at
// all. Those questions are answerable from this data. "Who is the best
// receptionist" is not.

// TrendPoint is one column of the gym's rhythm — a day, or a week when the
// span is too long to read day by day.
type TrendPoint struct {
	Key   string `json:"key"`
	Label string `json:"label"`

	Count         int   `json:"count"`
	AmountInPaise int64 `json:"amount_in_paise"`

	// True when nothing at all was recorded. Kept as an explicit zero rather
	// than an absent column: a gap in a series reads as missing data, and a
	// day the gym recorded nothing is a fact worth seeing.
	Quiet bool `json:"quiet"`
}

// CategoryTotal is how much work each ledger carried.
type CategoryTotal struct {
	Category string `json:"category"`
	Label    string `json:"label"`

	Count         int   `json:"count"`
	AmountInPaise int64 `json:"amount_in_paise"`

	// Share of all recorded work, 0-100. Rounded for display only; the counts
	// above are the truth.
	SharePct int `json:"share_pct"`
}

// PersonTrend is one person against their own previous period.
//
// Deliberately carries no rank, no score and no severity. The only comparison
// available to a client is the one to [PreviousCount], which is the same
// person a month ago.
type PersonTrend struct {
	UserID *int64 `json:"user_id,omitempty"`
	Name   string `json:"name"`
	Role   string `json:"role,omitempty"`

	Count         int   `json:"count"`
	AmountInPaise int64 `json:"amount_in_paise"`

	// The equivalent span immediately before this one, for the same person.
	PreviousCount int `json:"previous_count"`

	// Percentage change against themselves. Null when there is no previous
	// period to compare against — a new joiner is not down 100%.
	ChangePct *int `json:"change_pct,omitempty"`
}

// StaffAnalytics backs GET /api/v1/staff-work/analytics.
type StaffAnalytics struct {
	From string `json:"from"`
	To   string `json:"to"`
	Days int    `json:"days"`

	// "day" or "week".
	TrendUnit string       `json:"trend_unit"`
	Trend     []TrendPoint `json:"trend"`

	Categories []CategoryTotal `json:"categories"`

	// Ordered by name. Never by output.
	People []PersonTrend `json:"people"`

	TotalCount         int   `json:"total_count"`
	TotalAmountInPaise int64 `json:"total_amount_in_paise"`

	// Work recorded with no signed-in user behind it. A data-quality figure,
	// not a person's figure — and on this gym's live data it has been the
	// majority of everything, which makes every per-person number below it
	// a partial picture. Reported at the top for that reason.
	UnattributedCount int `json:"unattributed_count"`
	UnattributedPct   int `json:"unattributed_pct"`

	// Days inside the span where nothing was recorded at all.
	QuietDays int `json:"quiet_days"`
}

// TrendByWeek is the span length past which daily columns stop being legible.
const TrendByWeek = 62
