package plans

import (
	"context"
	"fmt"

	"gymcrm/internal/database"
	"gymcrm/internal/shared/pagination"
)

// Service contains all membership plan business logic.
type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// ─── Create ───────────────────────────────────────────────────────────────────

func (s *Service) CreatePlan(ctx context.Context, req CreatePlanRequest) (*PlanResponse, error) {
	tc := database.MustGetTenant(ctx)

	// Case-insensitive name uniqueness within this gym
	exists, err := s.repo.NameExistsInGym(ctx, req.Name, 0)
	if err != nil {
		return nil, fmt.Errorf("create plan: check name: %w", err)
	}
	if exists {
		return nil, ErrPlanNameExists
	}

	plan := &MembershipPlan{
		GymID:        tc.GymID(), // always from JWT, never from request
		Name:         req.Name,
		DurationDays: req.DurationDays,
		PriceInPaise: req.PriceInPaise,
		IsActive:     true,
	}

	if req.Description != "" {
		plan.Description = &req.Description
	}

	if err := s.repo.Create(ctx, plan); err != nil {
		return nil, fmt.Errorf("create plan: %w", err)
	}

	resp := ToResponse(plan)
	return &resp, nil
}

// ─── Read ─────────────────────────────────────────────────────────────────────

func (s *Service) GetPlan(ctx context.Context, id int64) (*PlanResponse, error) {
	plan, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("get plan: %w", err)
	}
	if plan == nil {
		return nil, ErrPlanNotFound
	}
	resp := ToResponse(plan)
	return &resp, nil
}

func (s *Service) ListPlans(ctx context.Context, req ListPlansRequest) ([]PlanResponse, int64, error) {
	plans, total, err := s.repo.List(ctx, req)
	if err != nil {
		return nil, 0, fmt.Errorf("list plans: %w", err)
	}
	return ToResponseList(plans), total, nil
}

func (s *Service) ListActivePlans(ctx context.Context, p pagination.Params) ([]PlanResponse, int64, error) {
	plans, total, err := s.repo.FindActive(ctx, p)
	if err != nil {
		return nil, 0, fmt.Errorf("list active plans: %w", err)
	}
	return ToResponseList(plans), total, nil
}

// ─── Update ───────────────────────────────────────────────────────────────────

func (s *Service) UpdatePlan(ctx context.Context, id int64, req UpdatePlanRequest) (*PlanResponse, error) {
	existing, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("update plan: %w", err)
	}
	if existing == nil {
		return nil, ErrPlanNotFound
	}

	// Case-insensitive name uniqueness — exclude current plan from check
	if req.Name != nil {
		exists, err := s.repo.NameExistsInGym(ctx, *req.Name, id)
		if err != nil {
			return nil, fmt.Errorf("update plan: check name: %w", err)
		}
		if exists {
			return nil, ErrPlanNameExists
		}
	}

	updates := make(map[string]interface{})

	if req.Name != nil {
		updates["name"] = *req.Name
	}
	if req.DurationDays != nil {
		updates["duration_days"] = *req.DurationDays
	}
	if req.PriceInPaise != nil {
		updates["price_in_paise"] = *req.PriceInPaise
	}
	if req.IsActive != nil {
		updates["is_active"] = *req.IsActive
	}

	if req.Description != nil {
		if *req.Description == "" {
			updates["description"] = nil
		} else {
			updates["description"] = *req.Description
		}
	}

	if len(updates) == 0 {
		resp := ToResponse(existing)
		return &resp, nil
	}

	if err := s.repo.Update(ctx, id, updates); err != nil {
		return nil, fmt.Errorf("update plan: %w", err)
	}

	updated, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("update plan: re-fetch: %w", err)
	}
	resp := ToResponse(updated)
	return &resp, nil
}

// ─── Delete ───────────────────────────────────────────────────────────────────

func (s *Service) DeletePlan(ctx context.Context, id int64) error {
	existing, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return fmt.Errorf("delete plan: %w", err)
	}
	if existing == nil {
		return ErrPlanNotFound
	}

	if err := s.repo.SoftDelete(ctx, id); err != nil {
		return fmt.Errorf("delete plan: %w", err)
	}
	return nil
}

// ─── Cross-module helpers ─────────────────────────────────────────────────────

// IsAssignable checks if a plan can be assigned to a member or renewal.
// Returns ErrPlanNotFound if the plan doesn't exist in this gym.
// Returns ErrPlanInactive if the plan exists but is not active.
// Called by: members service (assign plan), renewals service (create renewal).
func (s *Service) IsAssignable(ctx context.Context, planID int64) error {
	plan, err := s.repo.FindByID(ctx, planID)
	if err != nil {
		return fmt.Errorf("check plan assignable: %w", err)
	}
	if plan == nil {
		return ErrPlanNotFound
	}
	if !plan.IsActive {
		return ErrPlanInactive
	}
	return nil
}

// CountMembersUsingPlan returns member count for dashboard and lifecycle use.
// Exposed as a service method so future handlers can call it without
// touching the repository directly.
func (s *Service) CountMembersUsingPlan(ctx context.Context, planID int64) (int64, error) {
	// Verify plan exists in this gym before counting
	plan, err := s.repo.FindByID(ctx, planID)
	if err != nil {
		return 0, fmt.Errorf("count members using plan: %w", err)
	}
	if plan == nil {
		return 0, ErrPlanNotFound
	}

	count, err := s.repo.CountMembersUsingPlan(ctx, planID)
	if err != nil {
		return 0, fmt.Errorf("count members using plan: %w", err)
	}
	return count, nil
}
