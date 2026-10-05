package renewals

import "time"

// Renewal is an immutable financial audit record.
// Never soft-deleted, never modified after creation.
// One row = one paid membership extension.
//
// old_expiry_date: member's expiry BEFORE this renewal (NULL for first renewal)
// new_expiry_date: member's expiry AFTER this renewal (applied to members table)
// amount_paid_in_paise: actual amount collected — may differ from plan price
// renewal_date: business date (owner may backdate); created_at is system timestamp
type Renewal struct {
	ID                int64      `gorm:"primaryKey;autoIncrement"        json:"id"`
	GymID             int64      `gorm:"not null"                        json:"gym_id"`
	MemberID          int64      `gorm:"not null"                        json:"member_id"`
	PlanID            int64      `gorm:"not null"                        json:"plan_id"`
	AmountPaidInPaise int64      `gorm:"not null"                        json:"amount_paid_in_paise"`
	OldExpiryDate     *time.Time `gorm:"type:date"                       json:"old_expiry_date,omitempty"`
	NewExpiryDate     time.Time  `gorm:"type:date;not null"              json:"new_expiry_date"`
	RenewalDate       time.Time  `gorm:"type:date;not null"              json:"renewal_date"`
	RenewedByUserID   int64      `gorm:"not null"                        json:"renewed_by_user_id"`
	Notes             *string    `gorm:"type:text"                       json:"notes,omitempty"`
	CreatedAt         time.Time  `gorm:"autoCreateTime"                  json:"created_at"`
	UpdatedAt         time.Time  `gorm:"autoUpdateTime"                  json:"updated_at"`
}

func (Renewal) TableName() string { return "renewals" }
