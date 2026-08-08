package pt

import "errors"

var (
	ErrPackageNotFound     = errors.New("PT package not found")
	ErrTrainerNotFound     = errors.New("trainer not found")
	ErrMemberNotFound      = errors.New("member not found")
	ErrAppointmentNotFound = errors.New("appointment not found")

	ErrPackageNameRequired   = errors.New("package_name is required")
	ErrTotalSessionsRequired = errors.New("total_sessions must be greater than 0")
	ErrAmountNegative        = errors.New("amount_in_paise cannot be negative")

	ErrPackageNotActive        = errors.New("this package is not active")
	ErrPackageExhausted        = errors.New("this package has no sessions remaining")
	ErrAppointmentNotScheduled = errors.New("this appointment is not in a scheduled state")
	ErrScheduledAtRequired     = errors.New("scheduled_at is required")
)
