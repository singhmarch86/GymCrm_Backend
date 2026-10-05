package members

import "errors"

var (
	// ErrMemberNotFound — member doesn't exist in this gym.
	// Deliberately doesn't say "in this gym" to the client — prevents probing.
	ErrMemberNotFound = errors.New("member not found")

	// ErrPhoneAlreadyExists — phone is already registered to another member in this gym.
	ErrPhoneAlreadyExists = errors.New("a member with this phone number already exists")

	// ErrInvalidStatus — status value not in allowed set.
	ErrInvalidStatus = errors.New("invalid member status")

	// ErrInvalidDateRange — expiry_date is before start_date.
	ErrInvalidDateRange = errors.New("expiry_date must be after start_date")

	// ErrPlanNotFound — membership_plan_id doesn't exist in this gym.
	ErrPlanNotFound = errors.New("membership plan not found")
)
