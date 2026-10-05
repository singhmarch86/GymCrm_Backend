package users

import "errors"

var (
	ErrUserNotFound  = errors.New("staff member not found")
	ErrNameRequired  = errors.New("name is required")
	ErrPhoneRequired = errors.New("phone is required")
	ErrPhoneTaken    = errors.New("that phone number is already registered")
	ErrInvalidRole   = errors.New("role must be either 'owner' or 'staff'")
	ErrInvalidStatus = errors.New("status must be either 'active' or 'inactive'")
	ErrWeakPassword  = errors.New("password must be at least 8 characters and contain a digit")
	ErrLongPassword  = errors.New("password must not exceed 72 characters")

	// Lockout guards — a gym must always keep one active owner, and you cannot
	// remove your own access from under yourself.
	ErrLastActiveOwner      = errors.New("this is the gym's only active owner — promote another owner first")
	ErrCannotDeactivateSelf = errors.New("you cannot deactivate your own account")
	ErrCannotDemoteSelf     = errors.New("you cannot change your own role")
)
