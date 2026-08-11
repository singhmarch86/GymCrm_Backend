package leads

import "errors"

var (
	ErrLeadNotFound             = errors.New("lead not found")
	ErrPhoneRequired            = errors.New("phone is required")
	ErrNameRequired             = errors.New("name is required")
	ErrInvalidSource            = errors.New("invalid lead source")
	ErrInvalidStatus            = errors.New("invalid lead status")
	ErrLostReasonRequired       = errors.New("lost_reason is required when marking a lead as lost")
	ErrAlreadyConverted         = errors.New("lead has already been converted to a member")
	ErrInvalidLeadForConversion = errors.New("lead must be in trial_completed or joined status to convert")
	ErrInvalidActivityType      = errors.New("invalid activity type: expected one of call, note, follow_up_set, trial_scheduled")
	ErrInvalidOutcome           = errors.New("invalid outcome: expected one of answered, no_answer, call_back, interested, not_interested, wrong_number")
	// Server-written history (stage_change, created, converted, lost) carries
	// no outcome: a client able to tag one could rewrite what the funnel
	// analytics report.
	ErrOutcomeNotAllowed = errors.New("this activity type does not take an outcome")
)
