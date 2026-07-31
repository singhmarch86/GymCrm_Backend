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
}

func (Gym) TableName() string { return "gyms" }

type GymStatus string

const (
	GymStatusActive    GymStatus = "active"
	GymStatusSuspended GymStatus = "suspended"
	GymStatusInactive  GymStatus = "inactive"
)
