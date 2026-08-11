package referrals

import "time"

// Status. Mirrors chk_referrals_status in migration 014.
const (
	StatusPending  = "pending"
	StatusJoined   = "joined"
	StatusRewarded = "rewarded"
	StatusExpired  = "expired"
)

// Referral tracks one member-to-member referral. Reward is FREE DAYS added
// to the referrer's membership on payout — never cash, never automatic.
// This matches the reward_days field already present in the Flutter model
// before any backend existed for this feature.
type Referral struct {
	ID               int64 `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID            int64 `gorm:"not null"                 json:"gym_id"`
	ReferrerMemberID int64 `gorm:"not null"                 json:"referrer_member_id"`

	ReferredName     string `gorm:"not null" json:"referred_name"`
	ReferredPhone    string `gorm:"not null" json:"referred_phone"`
	ReferredLeadID   *int64 `json:"referred_lead_id,omitempty"`
	ReferredMemberID *int64 `json:"referred_member_id,omitempty"`

	Status string `gorm:"type:varchar(20);not null;default:'pending'" json:"status"`

	RewardDays    *int       `json:"reward_days,omitempty"`
	RewardGivenAt *time.Time `json:"reward_given_at,omitempty"`

	Notes           *string   `json:"notes,omitempty"`
	CreatedByUserID int64     `gorm:"not null" json:"created_by_user_id"`
	CreatedAt       time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt       time.Time `gorm:"autoUpdateTime" json:"updated_at"`
}

func (Referral) TableName() string { return "referrals" }

// memberSnapshot is the narrow subset of members this module touches —
// status to confirm the referrer is active, expiry_date to apply the reward.
// Same narrowness convention as lifecycle.memberSnapshot and
// classes.Repository.FindMemberStatus: no module but members/lifecycle has
// any business reading or writing a member's contact details.
type memberSnapshot struct {
	ID         int64
	Status     string
	ExpiryDate *time.Time
}
