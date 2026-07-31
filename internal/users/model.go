package users

import (
	"time"
)

type User struct {
	ID           int64      `gorm:"primaryKey;autoIncrement"          json:"id"`
	GymID        int64      `gorm:"not null;index"                    json:"gym_id"`
	Name         string     `gorm:"type:varchar(200);not null"        json:"name"`
	Phone        string     `gorm:"type:varchar(20);not null"         json:"phone"`
	Email        string     `gorm:"type:varchar(200)"                 json:"email"`
	PasswordHash string     `gorm:"type:varchar(255);not null"        json:"-"`
	Role         UserRole   `gorm:"type:varchar(20);not null;default:'staff'"  json:"role"`
	Status       UserStatus `gorm:"type:varchar(20);not null;default:'active'" json:"status"`
	CreatedAt    time.Time  `gorm:"autoCreateTime"                    json:"created_at"`
	UpdatedAt    time.Time  `gorm:"autoUpdateTime"                    json:"updated_at"`
	// Removed: Gym interface{} — caused GORM insert failure.
	// Cross-model joins are done explicitly in repository queries, never via GORM associations.
}

func (User) TableName() string { return "users" }

type UserRole string

const (
	RoleOwner UserRole = "owner"
	RoleStaff UserRole = "staff"
)

type UserStatus string

const (
	UserStatusActive   UserStatus = "active"
	UserStatusInactive UserStatus = "inactive"
)
