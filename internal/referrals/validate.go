package referrals

import "strings"

func validateCreate(req CreateReferralRequest) error {
	if req.ReferrerMemberID <= 0 {
		return ErrReferrerNotFound
	}
	if strings.TrimSpace(req.ReferredName) == "" {
		return ErrReferredNameRequired
	}
	if strings.TrimSpace(req.ReferredPhone) == "" {
		return ErrReferredPhoneRequired
	}
	return nil
}

func validateReward(req RewardRequest) error {
	if req.RewardDays <= 0 {
		return ErrRewardDaysRequired
	}
	return nil
}
