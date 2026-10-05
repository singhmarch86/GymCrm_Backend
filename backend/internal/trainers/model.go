package trainers

import "time"

const (
	StatusActive   = "active"
	StatusInactive = "inactive"
)

// Trainer is a PT roster entry with compensation details — not a users row.
// Many trainers never log into the app; this is deliberately independent of
// auth. Also unrelated to classes.trainer_user_id, which stays a users FK for
// group-class coverage. See docs/FR-03-trainers-pt-appointments.md §0.
type Trainer struct {
	ID    int64 `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID int64 `gorm:"not null"                 json:"gym_id"`

	FirstName      string  `gorm:"not null" json:"first_name"`
	LastName       string  `gorm:"not null" json:"last_name"`
	Phone          string  `gorm:"not null" json:"phone"`
	Email          *string `json:"email,omitempty"`
	Specialization *string `json:"specialization,omitempty"`

	Status        string   `gorm:"type:varchar(20);not null;default:'active'" json:"status"`
	SalaryInPaise *int64   `json:"salary_in_paise,omitempty"`
	CommissionPct *float64 `gorm:"type:numeric(5,2)" json:"commission_pct,omitempty"`

	CreatedAt time.Time  `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt time.Time  `gorm:"autoUpdateTime" json:"updated_at"`
	DeletedAt *time.Time `json:"-"`
}

func (Trainer) TableName() string { return "trainers" }
