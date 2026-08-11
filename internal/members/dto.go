package members

import "time"

// ─── Request DTOs ─────────────────────────────────────────────────────────────

type CreateMemberRequest struct {
	FirstName        string `json:"first_name"`
	LastName         string `json:"last_name"`
	Phone            string `json:"phone"`
	Email            string `json:"email"`
	Gender           string `json:"gender"`
	DateOfBirth      string `json:"date_of_birth"`
	Address          string `json:"address"`
	MembershipPlanID *int64 `json:"membership_plan_id"`
	StartDate        string `json:"start_date"`
	ExpiryDate       string `json:"expiry_date"`
	Notes            string `json:"notes"`
}

type UpdateMemberRequest struct {
	FirstName        *string `json:"first_name"`
	LastName         *string `json:"last_name"`
	Phone            *string `json:"phone"`
	Email            *string `json:"email"`
	Gender           *string `json:"gender"`
	Address          *string `json:"address"`
	MembershipPlanID *int64  `json:"membership_plan_id"`
	StartDate        *string `json:"start_date"`
	ExpiryDate       *string `json:"expiry_date"`
	Status           *string `json:"status"`
	Notes            *string `json:"notes"`
}

type ListMembersRequest struct {
	Page    int
	PerPage int
	Status  string
	Search  string
}

type ExpiringMembersRequest struct {
	Page    int
	PerPage int
	Days    int
}

// ─── Response DTOs ────────────────────────────────────────────────────────────

type MemberResponse struct {
	ID               int64      `json:"id"`
	GymID            int64      `json:"gym_id"`
	FirstName        string     `json:"first_name"`
	LastName         string     `json:"last_name"`
	FullName         string     `json:"full_name"`
	Phone            string     `json:"phone"`
	Email            *string    `json:"email,omitempty"`
	Gender           *string    `json:"gender,omitempty"`
	DateOfBirth      *time.Time `json:"date_of_birth,omitempty"`
	Address          *string    `json:"address,omitempty"`
	MembershipPlanID *int64     `json:"membership_plan_id,omitempty"`
	// Resolved by a JOIN in the list path and by a lookup on the detail path.
	// Populated everywhere it is advertised — a field declared in a response
	// and never filled is worse than an absent one, because a client can
	// reasonably code against it.
	MembershipPlanName *string `json:"membership_plan_name,omitempty"`

	// When they last came in (FR-17 §2). Nil means never — a real answer, and
	// for a new member the expected one.
	LastVisitAt *time.Time `json:"last_visit_at,omitempty"`
	StartDate   *time.Time `json:"start_date,omitempty"`
	ExpiryDate  *time.Time `json:"expiry_date,omitempty"`
	Status      string     `json:"status"`
	Notes       *string    `json:"notes,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
}

type MemberListResponse struct {
	Members []MemberResponse `json:"members"`
}

// ─── Mapper ───────────────────────────────────────────────────────────────────

// ToResponse converts a Member to its response DTO.
// planName is resolved separately by the service (members package does not
// import plans package — see repository.FindPlanNameByID). Pass "" if unknown
// or if the member has no plan assigned.
func ToResponse(m *Member, planName string) MemberResponse {
	resp := MemberResponse{
		ID:               m.ID,
		GymID:            m.GymID,
		FirstName:        m.FirstName,
		LastName:         m.LastName,
		FullName:         m.FullName(),
		Phone:            m.Phone,
		Email:            m.Email,
		Gender:           m.Gender,
		DateOfBirth:      m.DateOfBirth,
		Address:          m.Address,
		MembershipPlanID: m.MembershipPlanID,
		StartDate:        m.StartDate,
		ExpiryDate:       m.ExpiryDate,
		Status:           string(m.Status),
		Notes:            m.Notes,
		CreatedAt:        m.CreatedAt,
		UpdatedAt:        m.UpdatedAt,
	}
	if planName != "" {
		resp.MembershipPlanName = &planName
	}
	return resp
}

// ToResponseList maps members without resolving plan names — used by list
// endpoints where N+1 plan lookups would be wasteful. Plan name enrichment
// for list views happens via a single batched lookup in the service layer
// where needed (e.g. DueForRenewal), not here.
func ToResponseList(members []Member) []MemberResponse {
	out := make([]MemberResponse, 0, len(members))
	for i := range members {
		out = append(out, ToResponse(&members[i], ""))
	}
	return out
}

// ─── Renewals due view ────────────────────────────────────────────────────────

// ExpiryStatus buckets a member's renewal urgency. Computed at request time
// in Go (not stored) because "today" / "this week" are relative to now.
type ExpiryStatus string

const (
	ExpiryStatusExpired  ExpiryStatus = "EXPIRED"
	ExpiryStatusToday    ExpiryStatus = "DUE_TODAY"
	ExpiryStatusSoon     ExpiryStatus = "EXPIRING_SOON" // within 7 days
	ExpiryStatusUpcoming ExpiryStatus = "UPCOMING"      // within 30 days
	ExpiryStatusOK       ExpiryStatus = "ACTIVE"        // > 30 days out
)

// RenewalDueResponse is a single row on the Renewals screen.
// Matches the PRD's requested shape: id, memberName, phone, planName,
// expiryDate, daysRemaining, status.
// @Description A member due for renewal, with computed urgency fields.
type RenewalDueResponse struct {
	ID            int64      `json:"id"`
	MemberName    string     `json:"member_name"`
	Phone         string     `json:"phone"`
	PlanID        *int64     `json:"plan_id,omitempty"`
	PlanName      *string    `json:"plan_name,omitempty"`
	ExpiryDate    *time.Time `json:"expiry_date,omitempty"`
	DaysRemaining int        `json:"days_remaining"` // negative if expired
	Status        string     `json:"status"`         // ExpiryStatus value
}

// RenewalDueListResponse wraps the list for GET /api/v1/members/renewals.
// @Description List of members due for renewal, grouped client-side by status.
type RenewalDueListResponse struct {
	Renewals []RenewalDueResponse `json:"renewals"`
}

// ToRenewalDueResponse converts a joined repository row into the response DTO,
// computing days_remaining and status relative to "now".
func ToRenewalDueResponse(row MemberRenewalRow, now time.Time) RenewalDueResponse {
	resp := RenewalDueResponse{
		ID:         row.ID,
		MemberName: row.FirstName + " " + row.LastName,
		Phone:      row.Phone,
		PlanID:     row.PlanID,
		PlanName:   row.PlanName,
		ExpiryDate: row.ExpiryDate,
	}

	if row.ExpiryDate == nil {
		resp.Status = string(ExpiryStatusOK)
		return resp
	}

	today := now.Truncate(24 * time.Hour)
	expiry := row.ExpiryDate.Truncate(24 * time.Hour)
	days := int(expiry.Sub(today).Hours() / 24)
	resp.DaysRemaining = days

	switch {
	case days < 0:
		resp.Status = string(ExpiryStatusExpired)
	case days == 0:
		resp.Status = string(ExpiryStatusToday)
	case days <= 7:
		resp.Status = string(ExpiryStatusSoon)
	case days <= 30:
		resp.Status = string(ExpiryStatusUpcoming)
	default:
		resp.Status = string(ExpiryStatusOK)
	}

	return resp
}

// ─── Renew request ────────────────────────────────────────────────────────────

// RenewMemberRequest is the payload for POST /api/v1/members/{id}/renew.
// This is a convenience wrapper around the renewals module's CreateRenewal —
// it does not duplicate the expiry calculation logic.
// @Description Renew a member's membership using a plan.
type RenewMemberRequest struct {
	PlanID            int64  `json:"plan_id"`              // required
	StartDate         string `json:"start_date"`           // optional, YYYY-MM-DD, defaults to today
	AmountPaidInPaise int64  `json:"amount_paid_in_paise"` // required, > 0
	Notes             string `json:"notes"`                // optional
}

// ToDetailResponseList maps rows that already carry their plan name and last
// visit, so no per-row lookup happens here.
func ToDetailResponseList(rows []DetailRow) []MemberResponse {
	out := make([]MemberResponse, 0, len(rows))
	for i := range rows {
		resp := ToResponse(&rows[i].Member, "")
		resp.MembershipPlanName = rows[i].MembershipPlanName
		resp.LastVisitAt = rows[i].LastVisitAt
		out = append(out, resp)
	}
	return out
}
