package payments

import "time"

// Payment is the financial source of truth for a member's account.
// Renewals (the membership package) remain the source of truth for
// membership validity. The link between the two is owned by Renewals, not
// Payments: renewals.payment_id (added in migration 008, outside this
// package) points back at the Payment that funded it. Payment intentionally
// has no reference to Renewal — a payment can exist on its own (future:
// PT session fees, one-off charges) without ever needing an FK back to a
// renewal that may not exist.
//
//	Payment  → stores money: amount, mode, who collected it, when
//	Renewal  → stores membership validity: old/new expiry, duration
//
// Sprint 4 only ever creates rows with Status = "paid" — every payment is
// collected in a single atomic transaction alongside its renewal (see
// payments.Repository.CollectPayment). "pending" and "overdue" statuses are
// modelled here for forward compatibility with a future dues-generation
// job, but no endpoint in this sprint writes a "pending" row.
type Payment struct {
	ID       int64  `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID    int64  `gorm:"not null"                 json:"gym_id"`
	MemberID int64  `gorm:"not null"                 json:"member_id"`
	PlanID   *int64 `gorm:""                         json:"plan_id,omitempty"`

	AmountInPaise int64 `gorm:"not null"                 json:"amount_in_paise"`

	Status      PaymentStatus `gorm:"type:varchar(20);not null;default:'paid'" json:"status"`
	PaymentMode *PaymentMode  `gorm:"type:varchar(20)"                         json:"payment_mode,omitempty"`

	DueDate  *time.Time `gorm:"type:date" json:"due_date,omitempty"`
	PaidDate *time.Time `gorm:"type:date" json:"paid_date,omitempty"`

	CollectedByUserID *int64  `json:"collected_by_user_id,omitempty"`
	ReferenceNumber   *string `gorm:"type:varchar(100)" json:"reference_number,omitempty"`
	Notes             *string `gorm:"type:text"         json:"notes,omitempty"`

	CreatedAt time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt time.Time `gorm:"autoUpdateTime" json:"updated_at"`
}

func (Payment) TableName() string { return "payments" }

// AmountInRupees is a display helper. Never use for storage or calculations.
func (p *Payment) AmountInRupees() float64 {
	return float64(p.AmountInPaise) / 100
}

type PaymentStatus string

const (
	PaymentStatusPending PaymentStatus = "pending"
	PaymentStatusPaid    PaymentStatus = "paid"
	PaymentStatusOverdue PaymentStatus = "overdue"
)

type PaymentMode string

const (
	PaymentModeCash         PaymentMode = "cash"
	PaymentModeUPI          PaymentMode = "upi"
	PaymentModeCreditCard   PaymentMode = "credit_card"
	PaymentModeDebitCard    PaymentMode = "debit_card"
	PaymentModeBankTransfer PaymentMode = "bank_transfer"
)

// IsValidPaymentMode checks against the allowed set — mirrors the DB CHECK
// constraint so invalid values are rejected before hitting Postgres.
func IsValidPaymentMode(m string) bool {
	switch PaymentMode(m) {
	case PaymentModeCash, PaymentModeUPI, PaymentModeCreditCard, PaymentModeDebitCard, PaymentModeBankTransfer:
		return true
	default:
		return false
	}
}
