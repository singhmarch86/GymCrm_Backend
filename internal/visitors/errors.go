package visitors

import "errors"

var (
	ErrVisitorNotFound   = errors.New("visitor not found")
	ErrInvalidPurpose    = errors.New("purpose must be one of: trial, guest, tour, other")
	ErrAlreadyCheckedOut = errors.New("this visitor has already checked out")
	ErrAlreadyConverted  = errors.New("this visit has already been converted to a lead")
	ErrNameRequired      = errors.New("name is required")
)
