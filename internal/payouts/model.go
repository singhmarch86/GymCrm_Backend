package payouts

import (
	"errors"
	"time"
)

// Trainer payouts (FR-21 §2) — money the gym owes the people who work in it.
//
// The mirror of collections. That queue is money members owe the gym; this is
// money the gym owes trainers, and until now nothing recorded it at all.
//
// Three schemes run at once and any trainer may be on any combination:
//
//	salary      a fixed amount for a whole calendar month
//	commission  a percentage of personal training the gym has been PAID for
//	session     a rate per session actually delivered
//
// Commission accrues on money received, never on packages created. Paying a
// percentage of a package the gym has not collected is cash leaving against
// revenue that never arrived — the worst version of the leak this module
// exists to close.

var (
	ErrTrainerNotFound  = errors.New("payouts: no such trainer")
	ErrBadPeriod        = errors.New("payouts: period must be YYYY-MM-DD and end on or after start")
	ErrSalaryNeedsMonth = errors.New("payouts: a salaried trainer must be paid for a whole calendar month")
	ErrAlreadyExists    = errors.New("payouts: a payout already covers that period")
	ErrNotDraft         = errors.New("payouts: only a draft can be changed")
	ErrOwnerOnly        = errors.New("payouts: only an owner can record a payment")
	ErrNothingToPay     = errors.New("payouts: that period earns nothing")
)

// Statuses.
const (
	StatusDraft     = "draft"
	StatusPaid      = "paid"
	StatusCancelled = "cancelled"
)

// Line kinds.
const (
	KindSalary     = "salary"
	KindCommission = "commission"
	KindSession    = "session"
	KindAdjustment = "adjustment"
)

// PayoutLine is one component of a total, named so it can be checked.
type PayoutLine struct {
	ID          int64  `json:"id"`
	Kind        string `json:"kind"`
	ReferenceID *int64 `json:"reference_id,omitempty"`

	Description   string `json:"description"`
	AmountInPaise int64  `json:"amount_in_paise"`
}

// Payout is one trainer's earnings for one period.
type Payout struct {
	ID        int64  `json:"id"`
	TrainerID int64  `json:"trainer_id"`
	Trainer   string `json:"trainer"`

	PeriodStart time.Time `json:"period_start"`
	PeriodEnd   time.Time `json:"period_end"`

	// Kept apart so a trainer asking "why is this less than last month" can
	// see which part moved. A single total cannot answer that.
	SalaryInPaise     int64 `json:"salary_in_paise"`
	CommissionInPaise int64 `json:"commission_in_paise"`
	SessionsInPaise   int64 `json:"sessions_in_paise"`

	// Signed: an advance being recovered is negative.
	AdjustmentInPaise int64   `json:"adjustment_in_paise"`
	AdjustmentReason  *string `json:"adjustment_reason,omitempty"`

	TotalInPaise int64  `json:"total_in_paise"`
	Status       string `json:"status"`

	Notes *string `json:"notes,omitempty"`

	PaidAt          *time.Time `json:"paid_at,omitempty"`
	PaidBy          *string    `json:"paid_by,omitempty"`
	PaymentMode     *string    `json:"payment_mode,omitempty"`
	ReferenceNumber *string    `json:"reference_number,omitempty"`

	Lines []PayoutLine `json:"lines,omitempty"`

	CreatedAt time.Time `json:"created_at"`
}

// Preview is what a payout WOULD be, computed without writing anything.
//
// Exists because the alternative is creating a draft to find out, then
// cancelling it — which leaves abandoned rows in a money table and makes the
// audit trail noisy for anybody reading it later.
type Preview struct {
	TrainerID int64  `json:"trainer_id"`
	Trainer   string `json:"trainer"`

	PeriodStart string `json:"period_start"`
	PeriodEnd   string `json:"period_end"`

	SalaryInPaise     int64 `json:"salary_in_paise"`
	CommissionInPaise int64 `json:"commission_in_paise"`
	SessionsInPaise   int64 `json:"sessions_in_paise"`
	TotalInPaise      int64 `json:"total_in_paise"`

	Lines []PayoutLine `json:"lines"`

	// Already covered by a live payout for this period.
	AlreadyPaid bool `json:"already_paid"`

	// Commission the gym has NOT been paid for, so it is not in the figure
	// above. Reported rather than hidden: it is the argument for chasing those
	// dues, and a trainer who sold a package will ask about it.
	UncollectedInPaise int64 `json:"uncollected_in_paise"`
	UncollectedCount   int   `json:"uncollected_count"`
}
