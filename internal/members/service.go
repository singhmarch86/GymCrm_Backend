package members

import (
	"context"
	"fmt"
	"strings"
	"time"

	"gymcrm/internal/database"
	"gymcrm/internal/renewals"
	"gymcrm/internal/shared/pagination"
)

// Service contains all member business logic.
//
// renewalsSvc is injected so RenewMember() can delegate to the renewals
// module's existing CreateRenewal logic (expiry calculation, audit trail
// insert, member.expiry_date update) instead of duplicating it here.
// This is the one deliberate cross-module dependency in this package —
// documented because the project convention is "business modules never
// import each other." It mirrors the existing dashboard module's pattern
// of importing members/renewals/attendance directly.
type Service struct {
	repo        *Repository
	renewalsSvc *renewals.Service
}

func NewService(repo *Repository, renewalsSvc *renewals.Service) *Service {
	return &Service{repo: repo, renewalsSvc: renewalsSvc}
}

// ─── Create ───────────────────────────────────────────────────────────────────

func (s *Service) CreateMember(ctx context.Context, req CreateMemberRequest) (*MemberResponse, error) {
	tc := database.MustGetTenant(ctx)

	exists, err := s.repo.PhoneExistsInGym(ctx, req.Phone, 0)
	if err != nil {
		return nil, fmt.Errorf("create member: check phone: %w", err)
	}
	if exists {
		return nil, ErrPhoneAlreadyExists
	}

	member := &Member{
		GymID:            tc.GymID(),
		FirstName:        req.FirstName,
		LastName:         req.LastName,
		Phone:            req.Phone,
		MembershipPlanID: req.MembershipPlanID,
		Status:           MemberStatusActive,
	}

	// Optional string fields — store NULL instead of empty string
	if req.Email != "" {
		member.Email = &req.Email
	}
	if req.Gender != "" {
		member.Gender = &req.Gender
	}
	if req.Address != "" {
		member.Address = &req.Address
	}
	if req.Notes != "" {
		member.Notes = &req.Notes
	}

	// Optional date fields
	if req.DateOfBirth != "" {
		t, _ := time.Parse(dateLayout, req.DateOfBirth)
		member.DateOfBirth = &t
	}
	if req.StartDate != "" {
		t, _ := time.Parse(dateLayout, req.StartDate)
		member.StartDate = &t
	}
	if req.ExpiryDate != "" {
		t, _ := time.Parse(dateLayout, req.ExpiryDate)
		member.ExpiryDate = &t
	}

	if err := s.repo.Create(ctx, member); err != nil {
		return nil, fmt.Errorf("create member: %w", err)
	}

	planName := ""
	if member.MembershipPlanID != nil {
		planName, _ = s.repo.FindPlanNameByID(ctx, *member.MembershipPlanID)
	}
	resp := ToResponse(member, planName)
	return &resp, nil
}

// ─── Read ─────────────────────────────────────────────────────────────────────

func (s *Service) GetMember(ctx context.Context, id int64) (*MemberResponse, error) {
	member, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("get member: %w", err)
	}
	if member == nil {
		return nil, ErrMemberNotFound
	}
	planName := ""
	if member.MembershipPlanID != nil {
		planName, _ = s.repo.FindPlanNameByID(ctx, *member.MembershipPlanID)
	}
	resp := ToResponse(member, planName)
	return &resp, nil
}

func (s *Service) ListMembers(ctx context.Context, req ListMembersRequest) ([]MemberResponse, int64, error) {
	members, total, err := s.repo.List(ctx, req)
	if err != nil {
		return nil, 0, fmt.Errorf("list members: %w", err)
	}
	return ToResponseList(members), total, nil
}

func (s *Service) SearchMembers(ctx context.Context, query string, p pagination.Params) ([]MemberResponse, int64, error) {
	if query == "" {
		return []MemberResponse{}, 0, nil
	}
	members, total, err := s.repo.Search(ctx, query, p)
	if err != nil {
		return nil, 0, fmt.Errorf("search members: %w", err)
	}
	return ToResponseList(members), total, nil
}

func (s *Service) GetExpiringMembers(ctx context.Context, days int, p pagination.Params) ([]MemberResponse, int64, error) {
	if days <= 0 {
		days = 7
	}
	if days > 90 {
		days = 90
	}
	members, total, err := s.repo.FindExpiring(ctx, days, p)
	if err != nil {
		return nil, 0, fmt.Errorf("expiring members: %w", err)
	}
	return ToResponseList(members), total, nil
}

// ─── Update ───────────────────────────────────────────────────────────────────

func (s *Service) UpdateMember(ctx context.Context, id int64, req UpdateMemberRequest) (*MemberResponse, error) {
	existing, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("update member: %w", err)
	}
	if existing == nil {
		return nil, ErrMemberNotFound
	}

	if req.Phone != nil {
		exists, err := s.repo.PhoneExistsInGym(ctx, *req.Phone, id)
		if err != nil {
			return nil, fmt.Errorf("update member: check phone: %w", err)
		}
		if exists {
			return nil, ErrPhoneAlreadyExists
		}
	}

	updates := make(map[string]interface{})

	if req.FirstName != nil        { updates["first_name"] = *req.FirstName }
	if req.LastName != nil         { updates["last_name"] = *req.LastName }
	if req.Phone != nil            { updates["phone"] = *req.Phone }
	if req.MembershipPlanID != nil { updates["membership_plan_id"] = *req.MembershipPlanID }
	if req.Status != nil           { updates["status"] = *req.Status }

	// Pointer fields — empty string clears the value (sets NULL)
	if req.Email != nil {
		if *req.Email == "" {
			updates["email"] = nil
		} else {
			updates["email"] = *req.Email
		}
	}
	if req.Gender != nil {
		if *req.Gender == "" {
			updates["gender"] = nil
		} else {
			updates["gender"] = *req.Gender
		}
	}
	if req.Address != nil {
		if *req.Address == "" {
			updates["address"] = nil
		} else {
			updates["address"] = *req.Address
		}
	}
	if req.Notes != nil {
		if *req.Notes == "" {
			updates["notes"] = nil
		} else {
			updates["notes"] = *req.Notes
		}
	}

	if req.StartDate != nil {
		t, _ := time.Parse(dateLayout, *req.StartDate)
		updates["start_date"] = t
	}
	if req.ExpiryDate != nil {
		t, _ := time.Parse(dateLayout, *req.ExpiryDate)
		updates["expiry_date"] = t
	}

	if len(updates) == 0 {
		planName := ""
		if existing.MembershipPlanID != nil {
			planName, _ = s.repo.FindPlanNameByID(ctx, *existing.MembershipPlanID)
		}
		resp := ToResponse(existing, planName)
		return &resp, nil
	}

	if err := s.repo.Update(ctx, id, updates); err != nil {
		return nil, fmt.Errorf("update member: %w", err)
	}

	updated, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("update member: re-fetch: %w", err)
	}
	planName := ""
	if updated.MembershipPlanID != nil {
		planName, _ = s.repo.FindPlanNameByID(ctx, *updated.MembershipPlanID)
	}
	resp := ToResponse(updated, planName)
	return &resp, nil
}

// ─── Delete ───────────────────────────────────────────────────────────────────

func (s *Service) DeleteMember(ctx context.Context, id int64) error {
	existing, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return fmt.Errorf("delete member: %w", err)
	}
	if existing == nil {
		return ErrMemberNotFound
	}
	if err := s.repo.SoftDelete(ctx, id); err != nil {
		return fmt.Errorf("delete member: %w", err)
	}
	return nil
}

// ─── Renewals (Sprint 3) ──────────────────────────────────────────────────────

// RenewalFilter buckets the renewals screen's filter chips.
type RenewalFilter string

const (
	RenewalFilterAll       RenewalFilter = "all"
	RenewalFilterToday     RenewalFilter = "today"
	RenewalFilterTomorrow  RenewalFilter = "tomorrow"
	RenewalFilterThisWeek  RenewalFilter = "this_week"
	RenewalFilterExpired   RenewalFilter = "expired"
)

// GetDueForRenewal returns members relevant to the Renewals screen, filtered
// and searched in Go. Filtering happens here (not SQL) because "today",
// "tomorrow", and "this week" are relative to request time, and because the
// result set per gym is small (hundreds, not millions of rows) — a full SQL
// re-implementation of this bucketing isn't worth the complexity at this scale.
func (s *Service) GetDueForRenewal(ctx context.Context, filter RenewalFilter, search string) ([]RenewalDueResponse, error) {
	rows, err := s.repo.FindDueForRenewal(ctx)
	if err != nil {
		return nil, fmt.Errorf("due for renewal: %w", err)
	}

	now := time.Now().UTC()
	out := make([]RenewalDueResponse, 0, len(rows))

	for _, row := range rows {
		resp := ToRenewalDueResponse(row, now)

		if search != "" {
			term := strings.ToLower(strings.TrimSpace(search))
			name := strings.ToLower(resp.MemberName)
			phone := strings.ToLower(resp.Phone)
			if !strings.Contains(name, term) && !strings.Contains(phone, term) {
				continue
			}
		}

		if !matchesFilter(resp, filter) {
			continue
		}

		out = append(out, resp)
	}

	return out, nil
}

// matchesFilter applies the renewals screen's filter chip to a single row.
func matchesFilter(resp RenewalDueResponse, filter RenewalFilter) bool {
	switch filter {
	case RenewalFilterToday:
		return resp.Status == string(ExpiryStatusToday)
	case RenewalFilterTomorrow:
		return resp.DaysRemaining == 1
	case RenewalFilterThisWeek:
		return resp.DaysRemaining >= 0 && resp.DaysRemaining <= 7
	case RenewalFilterExpired:
		return resp.Status == string(ExpiryStatusExpired)
	case RenewalFilterAll, "":
		return true
	default:
		return true
	}
}

// RenewMember renews a member's membership via the renewals module.
// This is a thin wrapper — all expiry calculation, audit trail insertion,
// and member.expiry_date update logic lives in renewals.Service.CreateRenewal.
// We do not duplicate that logic here.
func (s *Service) RenewMember(ctx context.Context, memberID int64, req RenewMemberRequest) (*MemberResponse, error) {
	existing, err := s.repo.FindByID(ctx, memberID)
	if err != nil {
		return nil, fmt.Errorf("renew member: %w", err)
	}
	if existing == nil {
		return nil, ErrMemberNotFound
	}

	_, err = s.renewalsSvc.CreateRenewal(ctx, renewals.CreateRenewalRequest{
		MemberID:          memberID,
		PlanID:            req.PlanID,
		AmountPaidInPaise: req.AmountPaidInPaise,
		RenewalDate:       req.StartDate,
		Notes:             req.Notes,
	})
	if err != nil {
		return nil, fmt.Errorf("renew member: create renewal: %w", err)
	}

	// Re-fetch the member — renewalsSvc.CreateRenewal already updated expiry_date.
	updated, err := s.repo.FindByID(ctx, memberID)
	if err != nil {
		return nil, fmt.Errorf("renew member: re-fetch: %w", err)
	}
	planName, _ := s.repo.FindPlanNameByID(ctx, req.PlanID)
	resp := ToResponse(updated, planName)
	return &resp, nil
}
