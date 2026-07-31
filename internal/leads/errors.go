package leads

import "errors"

var (
	ErrLeadNotFound          = errors.New("lead not found")
	ErrPhoneRequired         = errors.New("phone is required")
	ErrNameRequired          = errors.New("name is required")
	ErrInvalidSource         = errors.New("invalid lead source")
	ErrInvalidStatus         = errors.New("invalid lead status")
	ErrLostReasonRequired    = errors.New("lost_reason is required when marking a lead as lost")
	ErrAlreadyConverted      = errors.New("lead has already been converted to a member")
	ErrInvalidLeadForConversion = errors.New("lead must be in trial_completed or joined status to convert")
	ErrInvalidActivityType      = errors.New("invalid activity type: expected one of call, note, follow_up_set, trial_scheduled")
)
