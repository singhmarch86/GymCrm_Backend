package visitors

import (
	"context"
	"fmt"
	"time"

	"gymcrm/internal/database"
	"gymcrm/internal/leads"
)

// Service holds visitor check-in/out logic. Converting a visit into a lead
// delegates to leads.Service rather than duplicating lead-creation rules —
// same cross-module pattern members already uses with renewals.
type Service struct {
	repo     *Repository
	leadsSvc *leads.Service
}

func NewService(repo *Repository, leadsSvc *leads.Service) *Service {
	return &Service{repo: repo, leadsSvc: leadsSvc}
}

func (s *Service) CheckIn(ctx context.Context, req CheckInRequest) (*VisitorResponse, error) {
	purpose, err := validateCheckIn(req)
	if err != nil {
		return nil, err
	}
	tc := database.MustGetTenant(ctx)

	v := &Visitor{
		GymID:           tc.GymID(),
		Name:            req.Name,
		Phone:           optionalText(req.Phone),
		Purpose:         purpose,
		HostStaffUserID: req.HostStaffUserID,
		Notes:           optionalText(req.Notes),
	}
	if err := s.repo.Create(ctx, v); err != nil {
		return nil, fmt.Errorf("check in: %w", err)
	}
	return s.get(ctx, v.ID)
}

func (s *Service) CheckOut(ctx context.Context, id int64) (*VisitorResponse, error) {
	existing, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("check out: find: %w", err)
	}
	if existing == nil {
		return nil, ErrVisitorNotFound
	}
	if existing.isCheckedOut() {
		return nil, ErrAlreadyCheckedOut
	}
	if err := s.repo.CheckOut(ctx, id); err != nil {
		return nil, fmt.Errorf("check out: %w", err)
	}
	return s.get(ctx, id)
}

// ConvertToLead turns a visit into a lead — an explicit staff action, never
// automatic. Reuses leads.Service.CreateLead so lead-creation rules live in
// exactly one place. source is always "walk_in": this IS how that lead
// originated, regardless of what the visitor's own "purpose" was.
func (s *Service) ConvertToLead(ctx context.Context, id int64, req ConvertToLeadRequest) (*VisitorResponse, error) {
	existing, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("convert to lead: find: %w", err)
	}
	if existing == nil {
		return nil, ErrVisitorNotFound
	}
	if existing.ConvertedLeadID != nil {
		return nil, ErrAlreadyConverted
	}

	phone := ""
	if existing.Phone != nil {
		phone = *existing.Phone
	}

	lead, err := s.leadsSvc.CreateLead(ctx, leads.CreateLeadRequest{
		Name:         existing.Name,
		Phone:        phone,
		Email:        req.Email,
		Gender:       req.Gender,
		Source:       "walk_in",
		Goal:         req.Goal,
		Notes:        derefOr(existing.Notes, ""),
		TrialDate:    req.TrialDate,
		FollowUpDate: req.FollowUpDate,
	})
	if err != nil {
		return nil, fmt.Errorf("convert to lead: create lead: %w", err)
	}

	if err := s.repo.SetConvertedLead(ctx, id, lead.ID); err != nil {
		return nil, fmt.Errorf("convert to lead: link: %w", err)
	}
	return s.get(ctx, id)
}

func (s *Service) List(ctx context.Context, from, to time.Time) ([]VisitorResponse, error) {
	rows, err := s.repo.List(ctx, from, to)
	if err != nil {
		return nil, fmt.Errorf("list visitors: %w", err)
	}
	out := make([]VisitorResponse, 0, len(rows))
	for _, r := range rows {
		out = append(out, toResponse(r))
	}
	return out, nil
}

func (s *Service) get(ctx context.Context, id int64) (*VisitorResponse, error) {
	row, err := s.repo.rowByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("get visitor: %w", err)
	}
	if row == nil {
		return nil, ErrVisitorNotFound
	}
	resp := toResponse(*row)
	return &resp, nil
}

func toResponse(r visitorRow) VisitorResponse {
	return VisitorResponse{
		ID: r.ID, Name: r.Name, Phone: r.Phone, Purpose: r.Purpose,
		CheckedInAt: r.CheckedInAt, CheckedOutAt: r.CheckedOutAt,
		HostStaffUserID: r.HostStaffUserID, HostStaffName: r.HostStaffName,
		ConvertedLeadID: r.ConvertedLeadID, Notes: r.Notes,
		StillInBuilding: r.CheckedOutAt == nil,
	}
}

func optionalText(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

func derefOr(s *string, def string) string {
	if s == nil {
		return def
	}
	return *s
}
