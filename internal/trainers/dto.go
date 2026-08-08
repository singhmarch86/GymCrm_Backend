package trainers

import "time"

// CreateTrainerRequest is the payload for POST /api/v1/trainers.
// @Description Add a trainer to the roster.
type CreateTrainerRequest struct {
	FirstName      string   `json:"first_name"`      // required
	LastName       string   `json:"last_name"`       // required
	Phone          string   `json:"phone"`           // required
	Email          string   `json:"email"`           // optional
	Specialization string   `json:"specialization"`  // optional
	SalaryInPaise  *int64   `json:"salary_in_paise"` // optional
	CommissionPct  *float64 `json:"commission_pct"`  // optional, 0-100
}

// UpdateTrainerRequest edits a trainer. All fields optional — only provided
// ones change.
// @Description Edit a trainer. Never affects PT packages already tied to them.
type UpdateTrainerRequest struct {
	FirstName      *string  `json:"first_name"`
	LastName       *string  `json:"last_name"`
	Phone          *string  `json:"phone"`
	Email          *string  `json:"email"`
	Specialization *string  `json:"specialization"`
	Status         *string  `json:"status"`
	SalaryInPaise  *int64   `json:"salary_in_paise"`
	CommissionPct  *float64 `json:"commission_pct"`
}

// TrainerResponse is the full trainer record.
// @Description A trainer roster entry.
type TrainerResponse struct {
	ID             int64    `json:"id"`
	FirstName      string   `json:"first_name"`
	LastName       string   `json:"last_name"`
	FullName       string   `json:"full_name"`
	Phone          string   `json:"phone"`
	Email          *string  `json:"email,omitempty"`
	Specialization *string  `json:"specialization,omitempty"`
	Status         string   `json:"status"`
	SalaryInPaise  *int64   `json:"salary_in_paise,omitempty"`
	CommissionPct  *float64 `json:"commission_pct,omitempty"`
	CreatedAt      time.Time `json:"created_at"`
}
