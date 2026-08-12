// Package staffwork answers one question: what happened today, and who did it.
//
// It writes nothing. Every number here is read back out of a ledger that
// already records the acting user — payments, renewals, sales, invoices,
// resolved retention alerts, lead activity, membership changes, wallet
// top-ups. See docs/FR-13-staff-work-dashboard.md for the rules and, more
// importantly, for what this deliberately refuses to compute.
package staffwork

import "time"

// Category is one source ledger. The categories are the ledgers by design
// (FR-13 §5) — inventing a taxonomy before a real gym describes their day
// would be guessing, and a wrong taxonomy is worse than none.
type Category string

const (
	CatPayments  Category = "payments"
	CatRenewals  Category = "renewals"
	CatSales     Category = "sales"
	CatInvoices  Category = "invoices"
	CatRetention Category = "retention"
	CatLeads     Category = "leads"
	CatLifecycle Category = "lifecycle"
	CatWallet    Category = "wallet"
)

// AllCategories is the display order: money first, then member work. Stable so
// the screen does not reshuffle between days.
var AllCategories = []Category{
	CatPayments, CatRenewals, CatSales, CatInvoices,
	CatRetention, CatLeads, CatLifecycle, CatWallet,
}

// Label is what a gym owner should see, in their words.
func (c Category) Label() string {
	switch c {
	case CatPayments:
		return "Payments collected"
	case CatRenewals:
		return "Renewals closed"
	case CatSales:
		return "Shop sales"
	case CatInvoices:
		return "Invoices raised"
	case CatRetention:
		return "At Risk handled"
	case CatLeads:
		return "Lead activity"
	case CatLifecycle:
		return "Membership changes"
	case CatWallet:
		return "Wallet top-ups"
	}
	return string(c)
}

// HasMoney reports whether a rupee total is meaningful for this category.
// Resolving an alert or logging a call moves no money, and showing ₹0 next to
// them would read as a failure rather than as "not applicable".
func (c Category) HasMoney() bool {
	switch c {
	case CatPayments, CatRenewals, CatSales, CatInvoices, CatWallet:
		return true
	}
	return false
}

func IsValidCategory(s string) bool {
	for _, c := range AllCategories {
		if Category(s) == c {
			return true
		}
	}
	return false
}

// Tally is one category's contribution to one person's day.
type Tally struct {
	Category Category `json:"category"`
	Label    string   `json:"label"`
	Count    int64    `json:"count"`

	// Money handled, in paise. Nil when the category moves no money — a
	// distinct thing from zero (FR-13 §6). Always "collected", never
	// "achieved": a receptionist taking a ₹40,000 renewal did not generate
	// ₹40,000 of value and the screen must not imply it.
	AmountInPaise *int64 `json:"amount_in_paise,omitempty"`
}

// StaffDay is one person's whole day.
type StaffDay struct {
	// Nil for the Unattributed row — work whose ledger row carries no user.
	// Shown, never hidden (FR-13 §3): a gym seeing "12 unattributed" learns
	// something true, probably that a login is being shared.
	UserID *int64  `json:"user_id,omitempty"`
	Name   string  `json:"name"`
	Role   *string `json:"role,omitempty"`

	Tallies []Tally `json:"tallies"`

	// Totals across every category, so the UI never has to re-add them and
	// cannot disagree with this package about the answer.
	TotalActions int64 `json:"total_actions"`
	TotalHandled int64 `json:"total_handled_in_paise"`

	// The earliest and latest thing recorded. Meaningful for one day ("worked
	// 07:10 to 21:40"), meaningless across a month — the UI is told which case
	// it is by DayReport.Days rather than having to guess from the dates.
	FirstActionAt *time.Time `json:"first_action_at,omitempty"`
	LastActionAt  *time.Time `json:"last_action_at,omitempty"`
}

// DayReport is the whole screen for one range (FR-18 §9).
//
// Named DayReport still, because a day is the common case and renaming it
// would churn every caller for nothing.
type DayReport struct {
	// Date is the gym's local day, and is only set when the range is one day.
	// Empty for a span: a month has no single date, and filling this with the
	// first day would let a careless reader label a month's totals "the 1st".
	Date string `json:"date,omitempty"`

	From string `json:"from"` // YYYY-MM-DD, inclusive
	To   string `json:"to"`   // YYYY-MM-DD, inclusive
	Days int    `json:"days"` // 1 for a single day

	Staff []StaffDay `json:"staff"`

	TotalActions int64 `json:"total_actions"`
	TotalHandled int64 `json:"total_handled_in_paise"`
}

// Item is one row behind a number (FR-13 §8). An aggregate nobody can drill
// into is an accusation, not a report.
type Item struct {
	Category      Category  `json:"category"`
	At            time.Time `json:"at"`
	Who           string    `json:"who"`  // the member or lead involved
	What          string    `json:"what"` // what was done
	AmountInPaise *int64    `json:"amount_in_paise,omitempty"`
}
