package renewals

import "time"

// ─── Request DTOs ─────────────────────────────────────────────────────────────

// CreateRenewalRequest is the payload for POST /api/v1/renewals.
// gym_id is never accepted here — always from JWT.
// renewed_by_user_id is never accepted here — always from JWT.
// @Description Create a renewal for a member. Extends their expiry date.
type CreateRenewalRequest struct {
	MemberID          int64  `json:"member_id"`            // required
	PlanID            int64  `json:"plan_id"`              // required, must be active
	AmountPaidInPaise int64  `json:"amount_paid_in_paise"` // required, > 0
	RenewalDate       string `json:"renewal_date"`         // optional, YYYY-MM-DD, defaults to today
	Notes             string `json:"notes"`                // optional
}

// ListRenewalsRequest holds query params for GET /api/v1/renewals.
type ListRenewalsRequest struct {
	Page     int
	PerPage  int
	MemberID *int64     // ?member_id=
	PlanID   *int64     // ?plan_id=
	DateFrom *time.Time // ?date_from=YYYY-MM-DD
	DateTo   *time.Time // ?date_to=YYYY-MM-DD
}

// ─── Response DTOs ────────────────────────────────────────────────────────────

// RenewalResponse is the full renewal record.
// Includes plan_name and member_name for Flutter display convenience —
// avoids extra round-trips to resolve IDs.
// @Description Full renewal audit record.
type RenewalResponse struct {
	ID                 int64      `json:"id"`
	GymID              int64      `json:"gym_id"`
	MemberID           int64      `json:"member_id"`
	MemberName         string     `json:"member_name"` // denormalised for display
	PlanID             int64      `json:"plan_id"`
	PlanName           string     `json:"plan_name"`          // denormalised for display
	PlanDurationDays   int        `json:"plan_duration_days"` // snapshot of plan at renewal time
	AmountPaidInPaise  int64      `json:"amount_paid_in_paise"`
	AmountPaidInRupees float64    `json:"amount_paid_in_rupees"` // display only
	OldExpiryDate      *time.Time `json:"old_expiry_date,omitempty"`
	NewExpiryDate      time.Time  `json:"new_expiry_date"`
	RenewalDate        time.Time  `json:"renewal_date"`
	RenewedByUserID    int64      `json:"renewed_by_user_id"`
	Notes              *string    `json:"notes,omitempty"`
	CreatedAt          time.Time  `json:"created_at"`
}

// RenewalListResponse wraps a slice of renewals.
// @Description Paginated renewal list.
type RenewalListResponse struct {
	Renewals []RenewalResponse `json:"renewals"`
}

// RenewalWithContext carries the renewal plus resolved names from joins.
// Used internally — never exposed directly.
type RenewalWithContext struct {
	Renewal
	MemberFirstName  string
	MemberLastName   string
	PlanName         string
	PlanDurationDays int
}

// ToResponse converts RenewalWithContext to the API response DTO.
func (r *RenewalWithContext) ToResponse() RenewalResponse {
	return RenewalResponse{
		ID:                 r.ID,
		GymID:              r.GymID,
		MemberID:           r.MemberID,
		MemberName:         r.MemberFirstName + " " + r.MemberLastName,
		PlanID:             r.PlanID,
		PlanName:           r.PlanName,
		PlanDurationDays:   r.PlanDurationDays,
		AmountPaidInPaise:  r.AmountPaidInPaise,
		AmountPaidInRupees: float64(r.AmountPaidInPaise) / 100,
		OldExpiryDate:      r.OldExpiryDate,
		NewExpiryDate:      r.NewExpiryDate,
		RenewalDate:        r.RenewalDate,
		RenewedByUserID:    r.RenewedByUserID,
		Notes:              r.Notes,
		CreatedAt:          r.CreatedAt,
	}
}

// ToResponseList maps a slice of RenewalWithContext to DTOs.
func ToResponseList(items []RenewalWithContext) []RenewalResponse {
	out := make([]RenewalResponse, 0, len(items))
	for i := range items {
		out = append(out, items[i].ToResponse())
	}
	return out
}
