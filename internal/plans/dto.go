package plans

import "time"

// ─── Request DTOs ─────────────────────────────────────────────────────────────

// CreatePlanRequest is the payload for POST /api/v1/plans.
// @Description Create a new membership plan for the gym.
type CreatePlanRequest struct {
	Name         string `json:"name"`           // required, trimmed, case-insensitive unique per gym
	Description  string `json:"description"`    // optional
	DurationDays int    `json:"duration_days"`  // required, > 0
	PriceInPaise int64  `json:"price_in_paise"` // required, > 0. ₹1,500 = 150000
}

// UpdatePlanRequest is the payload for PUT /api/v1/plans/{id}.
// All fields optional — only provided fields are updated.
// @Description Update a membership plan. Only provided fields are changed.
type UpdatePlanRequest struct {
	Name         *string `json:"name"`
	Description  *string `json:"description"`
	DurationDays *int    `json:"duration_days"`
	PriceInPaise *int64  `json:"price_in_paise"`
	IsActive     *bool   `json:"is_active"`
}

// ListPlansRequest holds query params for GET /api/v1/plans.
type ListPlansRequest struct {
	Page     int
	PerPage  int
	Search   string // ?search= matches plan name
	IsActive *bool  // ?active=true/false — nil means return all
}

// ─── Response DTOs ────────────────────────────────────────────────────────────

// PlanResponse is the safe plan representation.
// price_in_rupees is included as a convenience field for Flutter display.
// price_in_paise is the source of truth for all business logic.
// @Description Full membership plan record.
type PlanResponse struct {
	ID            int64     `json:"id"`
	GymID         int64     `json:"gym_id"`
	Name          string    `json:"name"`
	Description   *string   `json:"description,omitempty"`
	DurationDays  int       `json:"duration_days"`
	PriceInPaise  int64     `json:"price_in_paise"`
	PriceInRupees float64   `json:"price_in_rupees"` // display only — never use for calculations
	IsActive      bool      `json:"is_active"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

// PlanListResponse wraps a slice of plans.
// @Description Paginated plan list.
type PlanListResponse struct {
	Plans []PlanResponse `json:"plans"`
}

// ─── Mapper ───────────────────────────────────────────────────────────────────

func ToResponse(p *MembershipPlan) PlanResponse {
	return PlanResponse{
		ID:            p.ID,
		GymID:         p.GymID,
		Name:          p.Name,
		Description:   p.Description,
		DurationDays:  p.DurationDays,
		PriceInPaise:  p.PriceInPaise,
		PriceInRupees: p.PriceInRupees(),
		IsActive:      p.IsActive,
		CreatedAt:     p.CreatedAt,
		UpdatedAt:     p.UpdatedAt,
	}
}

func ToResponseList(plans []MembershipPlan) []PlanResponse {
	out := make([]PlanResponse, 0, len(plans))
	for i := range plans {
		out = append(out, ToResponse(&plans[i]))
	}
	return out
}
