package trainers

import "errors"

var (
	ErrNotFound          = errors.New("trainer not found")
	ErrNameRequired      = errors.New("first_name and last_name are required")
	ErrPhoneRequired     = errors.New("phone is required")
	ErrInvalidCommission = errors.New("commission_pct must be between 0 and 100")
)
