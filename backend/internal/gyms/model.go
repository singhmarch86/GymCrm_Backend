package gyms

import (
	"time"
)

type Gym struct {
	ID        int64     `gorm:"primaryKey;autoIncrement"                       json:"id"`
	Name      string    `gorm:"type:varchar(200);not null"                     json:"name"`
	OwnerName string    `gorm:"type:varchar(200);not null"                     json:"owner_name"`
	Phone     string    `gorm:"type:varchar(20);not null;uniqueIndex"          json:"phone"`
	Email     *string   `gorm:"type:varchar(200)"                              json:"email,omitempty"` // pointer — NULL when not provided
	Address   string    `gorm:"type:text"                                      json:"address,omitempty"`
	City      string    `gorm:"type:varchar(100);not null;default:'Ludhiana'"  json:"city"`
	State     string    `gorm:"type:varchar(100);not null;default:'Punjab'"    json:"state"`
	Status    GymStatus `gorm:"type:varchar(20);not null;default:'active'"     json:"status"`
	CreatedAt time.Time `gorm:"autoCreateTime"                                 json:"created_at"`
	UpdatedAt time.Time `gorm:"autoUpdateTime"                                 json:"updated_at"`

	// PlanTier is the pricing tier this gym is on — "normal" / "medium" /
	// "premium" (migration 037). internal/entitlements is what actually
	// reads and enforces this; kept as a plain string here rather than a
	// typed Tier so this package doesn't need to import entitlements.
	PlanTier string `gorm:"type:varchar(20);not null;default:'premium'" json:"plan_tier"`

	// Public advertisement profile (migration 036) — everything below is
	// meant to be shown to an anonymous visitor at /g/{PublicSlug}, unlike
	// every other field on this struct. Nil/empty until a gym owner fills
	// it in from the app; Published stays false until they explicitly turn
	// the page on (see internal/gyms/repository.go's GetPublicProfile).
	PublicSlug        *string  `gorm:"type:varchar(120);uniqueIndex"        json:"public_slug,omitempty"`
	Tagline           *string  `gorm:"type:varchar(200)"                    json:"tagline,omitempty"`
	PublicDescription *string  `gorm:"type:text"                            json:"public_description,omitempty"`
	CoverPhotoURL     *string  `gorm:"type:text"                            json:"cover_photo_url,omitempty"`
	Amenities         []string `gorm:"type:jsonb;serializer:json"           json:"amenities,omitempty"`
	PublicPhone       *string  `gorm:"type:varchar(20)"                     json:"public_phone,omitempty"`
	Published         bool     `gorm:"not null;default:false"               json:"published"`
}

func (Gym) TableName() string { return "gyms" }

type GymStatus string

const (
	GymStatusActive    GymStatus = "active"
	GymStatusSuspended GymStatus = "suspended"
	GymStatusInactive  GymStatus = "inactive"
)
