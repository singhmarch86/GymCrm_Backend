package payments

import "errors"

var (
	// ErrMemberNotFound — member doesn't exist in this gym.
	ErrMemberNotFound = errors.New("member not found")

	// ErrPlanNotFound — plan doesn't exist in this gym.
	ErrPlanNotFound = errors.New("plan not found")

	// ErrPlanInactive — plan exists but is not active.
	ErrPlanInactive = errors.New("plan is inactive and cannot be used for a payment")

	// ErrPaymentNotFound — payment doesn't exist in this gym.
	ErrPaymentNotFound = errors.New("payment not found")

	// ErrInvalidAmount — amount_in_paise must be > 0.
	ErrInvalidAmount = errors.New("amount must be greater than 0")

	// ErrInvalidPaymentMode — payment_mode not in the allowed set.
	ErrInvalidPaymentMode = errors.New("payment_mode must be one of: cash, upi, credit_card, debit_card, bank_transfer")
)
