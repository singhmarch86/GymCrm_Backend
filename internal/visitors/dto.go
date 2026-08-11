package visitors

import "time"

// CheckInRequest is the payload for POST /api/v1/visitors/check-in.
// gym_id comes from JWT.
// @Description Check in a walk-in visitor.
type CheckInRequest struct {
	Name            string `json:"name"`               // required
	Phone           string `json:"phone"`              // optional
	Purpose         string `json:"purpose"`            // optional, defaults to "trial"
	HostStaffUserID *int64 `json:"host_staff_user_id"` // optional
	Notes           string `json:"notes"`              // optional
}

// ConvertToLeadRequest turns a visit into a lead, reusing the leads module's
// creation logic rather than duplicating it. source defaults to "walk_in".
// @Description Convert a visit into a lead.
type ConvertToLeadRequest struct {
	Email        string `json:"email"`
	Gender       string `json:"gender"`
	Goal         string `json:"goal"`
	TrialDate    string `json:"trial_date"`
	FollowUpDate string `json:"follow_up_date"`
}

// VisitorResponse is the full visitor record.
// @Description A visitor check-in record.
type VisitorResponse struct {
	ID              int64      `json:"id"`
	Name            string     `json:"name"`
	Phone           *string    `json:"phone,omitempty"`
	Purpose         string     `json:"purpose"`
	CheckedInAt     time.Time  `json:"checked_in_at"`
	CheckedOutAt    *time.Time `json:"checked_out_at,omitempty"`
	HostStaffUserID *int64     `json:"host_staff_user_id,omitempty"`
	HostStaffName   *string    `json:"host_staff_name,omitempty"`
	ConvertedLeadID *int64     `json:"converted_lead_id,omitempty"`
	Notes           *string    `json:"notes,omitempty"`
	// StillInBuilding is true when checked_out_at is unset — the dominant
	// thing the front-desk screen actually wants to show at a glance.
	StillInBuilding bool `json:"still_in_building"`
}
