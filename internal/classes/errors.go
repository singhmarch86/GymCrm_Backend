package classes

import "errors"

// Domain errors. The handler maps these to HTTP status codes. Messages are
// written to be shown to front-desk/trainer staff verbatim.
var (
	ErrClassTypeNotFound = errors.New("class type not found")
	ErrClassTypeInactive = errors.New("this class type is no longer offered")
	ErrScheduleNotFound  = errors.New("class schedule not found")
	ErrSessionNotFound   = errors.New("class session not found")
	ErrMemberNotFound    = errors.New("member not found")
	ErrBookingNotFound   = errors.New("booking not found")

	// Schedule
	ErrInvalidDayOfWeek = errors.New("day_of_week must be between 0 (Sunday) and 6 (Saturday)")
	ErrInvalidDateRange = errors.New("effective_until cannot be before effective_from")

	// Session
	ErrSessionAlreadyCancelled = errors.New("this session is already cancelled")
	ErrSessionAlreadyCompleted = errors.New("this session is already completed")
	ErrCannotCancelCompleted   = errors.New("a completed session cannot be cancelled")

	// Booking
	ErrSessionAlreadyStarted  = errors.New("this session has already started")
	ErrSessionNotBookable     = errors.New("this session is cancelled and cannot be booked")
	ErrAlreadyBooked          = errors.New("this member already has an active booking for this session")
	ErrMemberFrozen           = errors.New("this member's membership is frozen and cannot book classes")
	ErrMemberTerminated       = errors.New("this member's membership has ended")
	ErrBookingAlreadyCancelled = errors.New("this booking is already cancelled")
	ErrCannotMarkBeforeSession = errors.New("attendance can only be marked after the session")
)
