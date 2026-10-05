package leads

import "time"

// ─── Request DTOs ─────────────────────────────────────────────────────────────

// CreateLeadRequest is the payload for POST /api/v1/leads.
// gym_id always comes from JWT.
type CreateLeadRequest struct {
	Name           string `json:"name"`             // required
	Phone          string `json:"phone"`            // required
	Email          string `json:"email"`            // optional
	Gender         string `json:"gender"`           // optional
	Source         string `json:"source"`           // required
	Goal           string `json:"goal"`             // optional
	Notes          string `json:"notes"`            // optional
	TrialDate      string `json:"trial_date"`       // optional YYYY-MM-DD
	FollowUpDate   string `json:"follow_up_date"`   // optional YYYY-MM-DD
	AssignedUserID *int64 `json:"assigned_user_id"` // optional
}

// UpdateLeadRequest is the payload for PUT /api/v1/leads/{id}.
// All fields optional — only provided fields are updated.
type UpdateLeadRequest struct {
	Name           *string `json:"name"`
	Phone          *string `json:"phone"`
	Email          *string `json:"email"`
	Gender         *string `json:"gender"`
	Source         *string `json:"source"`
	Goal           *string `json:"goal"`
	Notes          *string `json:"notes"`
	Status         *string `json:"status"`
	TrialDate      *string `json:"trial_date"`
	FollowUpDate   *string `json:"follow_up_date"`
	LostReason     *string `json:"lost_reason"`
	AssignedUserID *int64  `json:"assigned_user_id"`
}

// AdvanceStatusRequest is the payload for PATCH /api/v1/leads/{id}/status.
type AdvanceStatusRequest struct {
	Status     string  `json:"status"`      // required — target pipeline stage
	LostReason *string `json:"lost_reason"` // required when status = "lost"

	// Why the lead moved, in the staff member's words. Optional, and stored on
	// the stage-change activity. Until this existed a move recorded *what*
	// happened and never *why*, except for lost — which is the one case the
	// gym had already decided it needed a reason for.
	Note *string `json:"note"`
}

// ─── Response DTOs ────────────────────────────────────────────────────────────

// LeadResponse is the full lead record returned to the client.
type LeadResponse struct {
	ID                int64      `json:"id"`
	GymID             int64      `json:"gym_id"`
	Name              string     `json:"name"`
	Phone             string     `json:"phone"`
	Email             *string    `json:"email,omitempty"`
	Gender            *string    `json:"gender,omitempty"`
	Source            string     `json:"source"`
	SourceLabel       string     `json:"source_label"` // display-friendly
	Goal              *string    `json:"goal,omitempty"`
	GoalLabel         *string    `json:"goal_label,omitempty"` // display-friendly
	Notes             *string    `json:"notes,omitempty"`
	Status            string     `json:"status"`
	StatusLabel       string     `json:"status_label"` // display-friendly
	TrialDate         *time.Time `json:"trial_date,omitempty"`
	FollowUpDate      *time.Time `json:"follow_up_date,omitempty"`
	LostReason        *string    `json:"lost_reason,omitempty"`
	AssignedUserID    *int64     `json:"assigned_user_id,omitempty"`
	AssignedUserName  string     `json:"assigned_user_name,omitempty"`
	ConvertedMemberID *int64     `json:"converted_member_id,omitempty"`
	CreatedAt         time.Time  `json:"created_at"`
	UpdatedAt         time.Time  `json:"updated_at"`
}

// LeadListResponse wraps a slice of leads.
type LeadListResponse struct {
	Leads []LeadResponse `json:"leads"`
}

// LeadSummaryResponse backs GET /api/v1/leads/summary — dashboard KPIs.
type LeadSummaryResponse struct {
	TotalLeads       int64            `json:"total_leads"`
	TodayLeads       int64            `json:"today_leads"`
	PendingFollowUps int64            `json:"pending_follow_ups"`
	TrialsScheduled  int64            `json:"trials_scheduled"`
	ConversionRate   float64          `json:"conversion_rate"` // joined / (joined+lost) * 100
	ByStatus         map[string]int64 `json:"by_status"`       // count per pipeline stage
	BySource         map[string]int64 `json:"by_source"`       // count per source
}

// ─── Conversion ───────────────────────────────────────────────────────────────

// ConvertLeadRequest is the payload for POST /api/v1/leads/{id}/convert.
// Name, phone, email, gender are pre-filled from the lead on the frontend —
// owner can override before submitting.
// @Description Convert a lead into a paying member in one transaction.
type ConvertLeadRequest struct {
	// Member fields (pre-filled from lead, editable)
	FirstName string `json:"first_name"` // required
	LastName  string `json:"last_name"`  // required
	Phone     string `json:"phone"`      // required
	Email     string `json:"email"`      // optional
	Gender    string `json:"gender"`     // optional

	// Payment fields
	PlanID          int64  `json:"plan_id"`          // required
	AmountInPaise   int64  `json:"amount_in_paise"`  // required, > 0
	PaymentMode     string `json:"payment_mode"`     // required
	ReferenceNumber string `json:"reference_number"` // optional
	Notes           string `json:"notes"`            // optional
}

// ConvertLeadResponse confirms the conversion with both IDs.
// @Description Result of a successful lead → member conversion.
type ConvertLeadResponse struct {
	Lead     LeadResponse `json:"lead"`
	MemberID int64        `json:"member_id"`
	Message  string       `json:"message"`
}

var sourceLabels = map[string]string{
	"walk_in":   "Walk-in",
	"referral":  "Referral",
	"instagram": "Instagram",
	"facebook":  "Facebook",
	"google":    "Google",
	"whatsapp":  "WhatsApp",
	"website":   "Website",
	"other":     "Other",
}

var goalLabels = map[string]string{
	"weight_loss":    "Weight Loss",
	"muscle_gain":    "Muscle Gain",
	"fitness":        "General Fitness",
	"sports":         "Sports",
	"rehabilitation": "Rehabilitation",
	"other":          "Other",
}

var statusLabels = map[string]string{
	"new_lead":        "New Lead",
	"contacted":       "Contacted",
	"trial_scheduled": "Trial Scheduled",
	"trial_completed": "Trial Completed",
	"joined":          "Joined",
	"lost":            "Lost",
}

func toLeadResponse(l *Lead) LeadResponse {
	resp := LeadResponse{
		ID:                l.ID,
		GymID:             l.GymID,
		Name:              l.Name,
		Phone:             l.Phone,
		Email:             l.Email,
		Gender:            l.Gender,
		Source:            string(l.Source),
		SourceLabel:       sourceLabels[string(l.Source)],
		Notes:             l.Notes,
		Status:            string(l.Status),
		StatusLabel:       statusLabels[string(l.Status)],
		TrialDate:         l.TrialDate,
		FollowUpDate:      l.FollowUpDate,
		LostReason:        l.LostReason,
		AssignedUserID:    l.AssignedUserID,
		AssignedUserName:  l.AssignedUserName,
		ConvertedMemberID: l.ConvertedMemberID,
		CreatedAt:         l.CreatedAt,
		UpdatedAt:         l.UpdatedAt,
	}
	if l.Goal != nil {
		g := string(*l.Goal)
		resp.Goal = &g
		label := goalLabels[g]
		resp.GoalLabel = &label
	}
	return resp
}

func toLeadResponseList(leads []Lead) []LeadResponse {
	out := make([]LeadResponse, 0, len(leads))
	for i := range leads {
		out = append(out, toLeadResponse(&leads[i]))
	}
	return out
}
