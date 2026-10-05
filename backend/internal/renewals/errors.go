package renewals

import "errors"

var (
	// ErrRenewalNotFound — renewal doesn't exist in this gym.
	ErrRenewalNotFound = errors.New("renewal not found")

	// ErrMemberNotFound — member doesn't exist in this gym.
	ErrMemberNotFound = errors.New("member not found")

	// ErrPlanNotFound — plan doesn't exist in this gym.
	ErrPlanNotFound = errors.New("plan not found")

	// ErrPlanInactive — plan exists but is not active.
	ErrPlanInactive = errors.New("plan is inactive and cannot be used for renewal")

	// ErrInvalidAmount — amount_paid_in_paise must be > 0.
	ErrInvalidAmount = errors.New("amount_paid_in_paise must be greater than 0")

	// ErrInvalidRenewalDate — renewal_date is not a valid date.
	ErrInvalidRenewalDate = errors.New("renewal_date must be in YYYY-MM-DD format")
)
