package attendance

import "errors"

var (
	// ErrMemberNotFound — member doesn't exist in this gym.
	ErrMemberNotFound = errors.New("member not found")

	// ErrAlreadyCheckedIn — member already checked in today.
	ErrAlreadyCheckedIn = errors.New("member already checked in today")

	// ErrAttendanceNotFound — attendance record doesn't exist in this gym.
	ErrAttendanceNotFound = errors.New("attendance record not found")

	// ErrInvalidDate — date parameter is not valid YYYY-MM-DD.
	ErrInvalidDate = errors.New("date must be in YYYY-MM-DD format")
)
