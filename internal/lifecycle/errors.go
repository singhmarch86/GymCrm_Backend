package lifecycle

import "errors"

// Domain errors. The handler maps these to HTTP status codes; nothing else
// should inspect them. Messages are written to be shown to front-desk staff
// verbatim — they explain what went wrong and what to do about it.
var (
	ErrMemberNotFound = errors.New("member not found")
	ErrPlanNotFound   = errors.New("membership plan not found")
	ErrPlanInactive   = errors.New("that plan is no longer offered")

	// Freeze
	ErrAlreadyFrozen      = errors.New("this membership is already frozen")
	ErrNotFrozen          = errors.New("this membership is not frozen")
	ErrFreezeTooShort     = errors.New("a freeze must be at least 7 days")
	ErrFreezeTooLong      = errors.New("a single freeze cannot exceed 90 days")
	ErrFreezeAllowanceHit = errors.New("this member has used their 90-day freeze allowance for the year")
	ErrCannotFreezeExpiry = errors.New("an expired membership cannot be frozen — renew it first")

	// Upgrade
	ErrSamePlan           = errors.New("the member is already on that plan")
	ErrUpgradeWhileFrozen = errors.New("unfreeze the membership before changing plan")

	// Transfer
	ErrTransferToSelf    = errors.New("a membership cannot be transferred to the same member")
	ErrTargetHasActive   = errors.New("the receiving member already has an active membership")
	ErrNothingToTransfer = errors.New("this membership has no remaining days to transfer")
	ErrCrossGymTransfer  = errors.New("memberships cannot be transferred between gyms")

	// Terminate
	ErrAlreadyTerminated = errors.New("this membership is already terminated")
	ErrReasonRequired    = errors.New("a reason is required to terminate a membership")

	// Effective dating
	ErrBackdatedTooFar      = errors.New("operations cannot be backdated more than 7 days")
	ErrFutureDatedTooFar    = errors.New("freezes cannot be scheduled more than 30 days ahead")
	ErrFutureDateNotAllowed = errors.New("only freezes may be dated in the future")
)
