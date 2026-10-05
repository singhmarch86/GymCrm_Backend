package plans

import (
	"time"

	"gorm.io/gorm"
)

// MembershipPlan is a gym's offering catalogue.
// Soft-deleted — renewals reference plan_id and must never be orphaned.
// Price in paise — avoids float arithmetic entirely. ₹1,500 = 150000 paise.
// Name stored as-entered but uniqueness enforced on LOWER(name) at DB level.
// No GORM associations — all cross-table joins are explicit in repository SQL.
type MembershipPlan struct {
	ID           int64          `gorm:"primaryKey;autoIncrement"                          json:"id"`
	GymID        int64          `gorm:"not null;index:idx_plans_gym"                      json:"gym_id"`
	Name         string         `gorm:"type:varchar(200);not null"                        json:"name"`
	Description  *string        `gorm:"type:text"                                         json:"description,omitempty"`
	DurationDays int            `gorm:"not null"                                          json:"duration_days"`
	PriceInPaise int64          `gorm:"not null"                                          json:"price_in_paise"`
	IsActive     bool           `gorm:"not null;default:true;index:idx_plans_gym"         json:"is_active"`
	CreatedAt    time.Time      `gorm:"autoCreateTime"                                    json:"created_at"`
	UpdatedAt    time.Time      `gorm:"autoUpdateTime"                                    json:"updated_at"`
	DeletedAt    gorm.DeletedAt `gorm:"index"                                             json:"-"`
}

func (MembershipPlan) TableName() string { return "membership_plans" }

// PriceInRupees returns display price. Never use for storage or business logic.
func (p *MembershipPlan) PriceInRupees() float64 {
	return float64(p.PriceInPaise) / 100
}
