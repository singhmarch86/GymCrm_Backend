package plans

import "errors"

var (
	// ErrPlanNotFound — plan doesn't exist in this gym.
	ErrPlanNotFound = errors.New("plan not found")

	// ErrPlanNameExists — case-insensitive name clash within the gym.
	ErrPlanNameExists = errors.New("a plan with this name already exists")

	// ErrPlanInactive — plan exists but is inactive, cannot be assigned.
	ErrPlanInactive = errors.New("plan is inactive")

	// ErrInvalidDuration — duration_days must be > 0.
	ErrInvalidDuration = errors.New("duration_days must be greater than 0")

	// ErrInvalidPrice — price_in_paise must be > 0.
	ErrInvalidPrice = errors.New("price_in_paise must be greater than 0")
)
