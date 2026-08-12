package leads

import (
	"context"
	"fmt"
	"strings"

	"gymcrm/internal/database"
	"gymcrm/internal/shared/pagination"
)

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) CreateLead(ctx context.Context, req CreateLeadRequest) (*LeadResponse, error) {
	tc := database.MustGetTenant(ctx)

	lead := &Lead{
		GymID:          tc.GymID(),
		Name:           req.Name,
		Phone:          req.Phone,
		Source:         LeadSource(req.Source),
		Status:         LeadStatusNew,
		AssignedUserID: req.AssignedUserID,
	}

	if req.Email != "" {
		lead.Email = &req.Email
	}
	if req.Gender != "" {
		lead.Gender = &req.Gender
	}
	if req.Goal != "" {
		g := LeadGoal(req.Goal)
		lead.Goal = &g
	}
	if req.Notes != "" {
		lead.Notes = &req.Notes
	}
	if t := parseDate(req.TrialDate); t != nil {
		lead.TrialDate = t
	}
	if t := parseDate(req.FollowUpDate); t != nil {
		lead.FollowUpDate = t
	}

	if err := s.repo.Create(ctx, lead); err != nil {
		return nil, fmt.Errorf("create lead: %w", err)
	}

	// Seed the timeline with an opening entry. Best-effort: a lead that exists
	// without its first activity row is a cosmetic gap in the feed, not a
	// reason to fail the caller's create.
	newStatus := string(LeadStatusNew)
	_ = s.repo.LogActivity(ctx, &LeadActivity{
		LeadID:   lead.ID,
		Type:     ActivityCreated,
		Note:     strPtrOrNil("Lead created from " + labelForSource(lead.Source)),
		ToStatus: &newStatus,
	})

	resp := toLeadResponse(lead)
	return &resp, nil
}

func (s *Service) GetLead(ctx context.Context, id int64) (*LeadResponse, error) {
	lead, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("get lead: %w", err)
	}
	if lead == nil {
		return nil, ErrLeadNotFound
	}
	resp := toLeadResponse(lead)
	return &resp, nil
}

func (s *Service) ListLeads(ctx context.Context, req ListRequest) ([]LeadResponse, int64, error) {
	leads, total, err := s.repo.List(ctx, req)
	if err != nil {
		return nil, 0, fmt.Errorf("list leads: %w", err)
	}
	return toLeadResponseList(leads), total, nil
}

func (s *Service) UpdateLead(ctx context.Context, id int64, req UpdateLeadRequest) (*LeadResponse, error) {
	existing, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("update lead: %w", err)
	}
	if existing == nil {
		return nil, ErrLeadNotFound
	}

	updates := make(map[string]interface{})

	if req.Name != nil {
		updates["name"] = strings.TrimSpace(*req.Name)
	}
	if req.Phone != nil {
		updates["phone"] = strings.TrimSpace(*req.Phone)
	}
	if req.Email != nil {
		e := strings.TrimSpace(*req.Email)
		if e == "" {
			updates["email"] = nil
		} else {
			updates["email"] = e
		}
	}
	if req.Gender != nil {
		updates["gender"] = *req.Gender
	}
	if req.Source != nil {
		if !IsValidSource(*req.Source) {
			return nil, ErrInvalidSource
		}
		updates["source"] = *req.Source
	}
	if req.Goal != nil {
		updates["goal"] = *req.Goal
	}
	if req.Notes != nil {
		updates["notes"] = *req.Notes
	}
	if req.Status != nil {
		if !IsValidStatus(*req.Status) {
			return nil, ErrInvalidStatus
		}
		updates["status"] = *req.Status
	}
	if req.TrialDate != nil {
		updates["trial_date"] = parseDate(*req.TrialDate)
	}
	if req.FollowUpDate != nil {
		updates["follow_up_date"] = parseDate(*req.FollowUpDate)
	}
	if req.LostReason != nil {
		updates["lost_reason"] = *req.LostReason
	}
	if req.AssignedUserID != nil {
		updates["assigned_user_id"] = req.AssignedUserID
	}

	if len(updates) == 0 {
		resp := toLeadResponse(existing)
		return &resp, nil
	}

	if err := s.repo.Update(ctx, id, updates); err != nil {
		return nil, fmt.Errorf("update lead: save: %w", err)
	}

	updated, err := s.repo.FindByID(ctx, id)
	if err != nil || updated == nil {
		return nil, fmt.Errorf("update lead: re-fetch: %w", err)
	}
	resp := toLeadResponse(updated)
	return &resp, nil
}

func (s *Service) AdvanceStatus(ctx context.Context, id int64, req AdvanceStatusRequest) (*LeadResponse, error) {
	existing, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("advance status: %w", err)
	}
	if existing == nil {
		return nil, ErrLeadNotFound
	}

	updates := map[string]interface{}{
		"status": req.Status,
	}
	if req.LostReason != nil {
		updates["lost_reason"] = *req.LostReason
	}

	// Record the transition alongside the update so the lead's timeline (and
	// the time-in-stage analytics derived from it) stays consistent with its
	// actual status even if the write fails partway.
	// The note wins when given; lost_reason is the fallback so a lost lead
	// with no note still carries its reason onto the timeline, as before.
	activityNote := req.Note
	if activityNote == nil || strings.TrimSpace(*activityNote) == "" {
		activityNote = req.LostReason
	}

	if err := s.repo.UpdateStatusWithActivity(
		ctx, id, string(existing.Status), req.Status, updates, activityNote,
	); err != nil {
		return nil, fmt.Errorf("advance status: save: %w", err)
	}

	updated, err := s.repo.FindByID(ctx, id)
	if err != nil || updated == nil {
		return nil, fmt.Errorf("advance status: re-fetch: %w", err)
	}
	resp := toLeadResponse(updated)
	return &resp, nil
}

func (s *Service) DeleteLead(ctx context.Context, id int64) error {
	existing, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return fmt.Errorf("delete lead: %w", err)
	}
	if existing == nil {
		return ErrLeadNotFound
	}
	return s.repo.SoftDelete(ctx, id)
}

func (s *Service) GetSummary(ctx context.Context) (*LeadSummaryResponse, error) {
	data, err := s.repo.GetSummary(ctx)
	if err != nil {
		return nil, fmt.Errorf("lead summary: %w", err)
	}

	resp := &LeadSummaryResponse{
		TotalLeads:       data.TotalLeads,
		TodayLeads:       data.TodayLeads,
		PendingFollowUps: data.PendingFollowUps,
		TrialsScheduled:  data.TrialsScheduled,
		ByStatus:         data.ByStatus,
		BySource:         data.BySource,
	}

	// Conversion rate: joined / (joined + lost) * 100
	terminal := data.JoinedCount + data.LostCount
	if terminal > 0 {
		resp.ConversionRate = float64(data.JoinedCount) / float64(terminal) * 100
	}

	return resp, nil
}

func (s *Service) ConvertToMember(ctx context.Context, leadID int64, req ConvertLeadRequest) (*ConvertLeadResponse, error) {
	// Validate required fields
	req.FirstName = strings.TrimSpace(req.FirstName)
	req.LastName = strings.TrimSpace(req.LastName)
	req.Phone = strings.TrimSpace(req.Phone)

	if req.FirstName == "" {
		return nil, fmt.Errorf("first_name is required")
	}
	if req.Phone == "" {
		return nil, fmt.Errorf("phone is required")
	}
	if req.PlanID <= 0 {
		return nil, fmt.Errorf("plan_id is required")
	}
	if req.AmountInPaise <= 0 {
		return nil, fmt.Errorf("amount_in_paise must be greater than 0")
	}
	if req.PaymentMode == "" {
		return nil, fmt.Errorf("payment_mode is required")
	}

	memberID, err := s.repo.ConvertToMember(ctx, ConversionInput{
		LeadID:          leadID,
		FirstName:       req.FirstName,
		LastName:        req.LastName,
		Phone:           req.Phone,
		Email:           req.Email,
		Gender:          req.Gender,
		PlanID:          req.PlanID,
		AmountInPaise:   req.AmountInPaise,
		PaymentMode:     req.PaymentMode,
		ReferenceNumber: req.ReferenceNumber,
		Notes:           req.Notes,
	})
	if err != nil {
		return nil, fmt.Errorf("convert lead: %w", err)
	}

	// Re-fetch updated lead for response
	lead, err := s.repo.FindByID(ctx, leadID)
	if err != nil || lead == nil {
		return nil, fmt.Errorf("convert lead: re-fetch: %w", err)
	}

	resp := toLeadResponse(lead)
	return &ConvertLeadResponse{
		Lead:     resp,
		MemberID: memberID,
		Message:  fmt.Sprintf("%s %s has been converted to a member", req.FirstName, req.LastName),
	}, nil
}

func (s *Service) ListPaginated(ctx context.Context, p pagination.Params, status, source, search, assignedTo string) ([]LeadResponse, int64, error) {
	return s.ListLeads(ctx, ListRequest{
		Page:       p.Page,
		PerPage:    p.PerPage,
		Status:     status,
		Source:     source,
		Search:     search,
		AssignedTo: assignedTo,
	})
}
