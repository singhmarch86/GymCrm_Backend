package referrals

import "errors"

var (
	ErrReferralNotFound     = errors.New("referral not found")
	ErrReferrerNotFound     = errors.New("referring member not found")
	ErrReferrerNotActive    = errors.New("only an active member can refer someone")
	ErrReferredNameRequired = errors.New("referred_name is required")
	ErrReferredPhoneRequired = errors.New("referred_phone is required")
	ErrNotPending           = errors.New("this referral is not pending")
	ErrNotJoined            = errors.New("this referral has not reached 'joined' status yet — mark it joined before rewarding")
	ErrRewardDaysRequired   = errors.New("reward_days is required and must be greater than 0")
	ErrAlreadyRewarded      = errors.New("this referral has already been rewarded")
)
