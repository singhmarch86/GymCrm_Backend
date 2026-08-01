package referrals

import "time"

// CreateReferralRequest is the payload for POST /api/v1/referrals.
// gym_id and created_by_user_id come from JWT.
// @Description Record a member referring someone. Referrer must be an active member.
type CreateReferralRequest struct {
	ReferrerMemberID int64  `json:"referrer_member_id"` // required
	ReferredName     string `json:"referred_name"`      // required
	ReferredPhone    string `json:"referred_phone"`     // required
	Notes            string `json:"notes"`              // optional
}

// MarkJoinedRequest links a referral to the member the referred person
// became, once they actually sign up.
// @Description Link a referral to the member it produced.
type MarkJoinedRequest struct {
	ReferredMemberID int64 `json:"referred_member_id"` // required
}

// RewardRequest pays out a joined referral as free days on the referrer's
// membership.
// @Description Reward a joined referral — extends the referrer's expiry by reward_days.
type RewardRequest struct {
	RewardDays int `json:"reward_days"` // required, > 0
}

// ReferralResponse is the full referral record, denormalised for display.
// @Description A referral record.
type ReferralResponse struct {
	ID                 int64      `json:"id"`
	ReferrerMemberID   int64      `json:"referrer_member_id"`
	ReferrerName       string     `json:"referrer_name"`
	ReferredName       string     `json:"referred_name"`
	ReferredPhone      string     `json:"referred_phone"`
	ReferredMemberID   *int64     `json:"referred_member_id,omitempty"`
	Status             string     `json:"status"`
	RewardDays         *int       `json:"reward_days,omitempty"`
	RewardGivenAt      *time.Time `json:"reward_given_at,omitempty"`
	Notes              *string    `json:"notes,omitempty"`
	CreatedByUserName  string     `json:"created_by_user_name"`
	CreatedAt          time.Time  `json:"created_at"`
}
