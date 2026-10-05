package trainers

import (
	"context"
	"fmt"
	"strings"

	"gymcrm/internal/database"
)

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

func (s *Service) Create(ctx context.Context, req CreateTrainerRequest) (*TrainerResponse, error) {
	if err := validateCreate(req); err != nil {
		return nil, err
	}
	tc := database.MustGetTenant(ctx)
	t := &Trainer{
		GymID:          tc.GymID(),
		FirstName:      strings.TrimSpace(req.FirstName),
		LastName:       strings.TrimSpace(req.LastName),
		Phone:          strings.TrimSpace(req.Phone),
		Email:          optionalText(req.Email),
		Specialization: optionalText(req.Specialization),
		Status:         StatusActive,
		SalaryInPaise:  req.SalaryInPaise,
		CommissionPct:  req.CommissionPct,
	}
	if err := s.repo.Create(ctx, t); err != nil {
		return nil, fmt.Errorf("create trainer: %w", err)
	}
	return toResponse(*t), nil
}

func (s *Service) List(ctx context.Context, activeOnly bool) ([]TrainerResponse, error) {
	list, err := s.repo.List(ctx, activeOnly)
	if err != nil {
		return nil, fmt.Errorf("list trainers: %w", err)
	}
	out := make([]TrainerResponse, 0, len(list))
	for _, t := range list {
		out = append(out, *toResponse(t))
	}
	return out, nil
}

func (s *Service) Update(ctx context.Context, id int64, req UpdateTrainerRequest) (*TrainerResponse, error) {
	if err := validateUpdate(req); err != nil {
		return nil, err
	}
	existing, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("update trainer: find: %w", err)
	}
	if existing == nil {
		return nil, ErrNotFound
	}

	mut := map[string]any{}
	if req.FirstName != nil {
		mut["first_name"] = strings.TrimSpace(*req.FirstName)
	}
	if req.LastName != nil {
		mut["last_name"] = strings.TrimSpace(*req.LastName)
	}
	if req.Phone != nil {
		mut["phone"] = strings.TrimSpace(*req.Phone)
	}
	if req.Email != nil {
		mut["email"] = optionalText(*req.Email)
	}
	if req.Specialization != nil {
		mut["specialization"] = optionalText(*req.Specialization)
	}
	if req.Status != nil {
		mut["status"] = *req.Status
	}
	if req.SalaryInPaise != nil {
		mut["salary_in_paise"] = *req.SalaryInPaise
	}
	if req.CommissionPct != nil {
		mut["commission_pct"] = *req.CommissionPct
	}
	if len(mut) > 0 {
		if err := s.repo.Update(ctx, id, mut); err != nil {
			return nil, fmt.Errorf("update trainer: %w", err)
		}
	}

	updated, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("update trainer: reload: %w", err)
	}
	return toResponse(*updated), nil
}

func toResponse(t Trainer) *TrainerResponse {
	return &TrainerResponse{
		ID: t.ID, FirstName: t.FirstName, LastName: t.LastName,
		FullName: t.FirstName + " " + t.LastName, Phone: t.Phone,
		Email: t.Email, Specialization: t.Specialization, Status: t.Status,
		SalaryInPaise: t.SalaryInPaise, CommissionPct: t.CommissionPct, CreatedAt: t.CreatedAt,
	}
}

func optionalText(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}
