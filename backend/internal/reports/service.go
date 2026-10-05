package reports

import (
	"context"
	"fmt"
)

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) GetRevenueReport(ctx context.Context) (*RevenueReport, error) {
	r, err := s.repo.GetRevenueReport(ctx)
	if err != nil {
		return nil, fmt.Errorf("revenue report: %w", err)
	}
	return r, nil
}

func (s *Service) GetMemberReport(ctx context.Context) (*MemberReport, error) {
	r, err := s.repo.GetMemberReport(ctx)
	if err != nil {
		return nil, fmt.Errorf("member report: %w", err)
	}
	return r, nil
}

func (s *Service) GetPaymentReport(ctx context.Context) (*PaymentReport, error) {
	r, err := s.repo.GetPaymentReport(ctx)
	if err != nil {
		return nil, fmt.Errorf("payment report: %w", err)
	}
	return r, nil
}

func (s *Service) GetRenewalReport(ctx context.Context) (*RenewalReport, error) {
	r, err := s.repo.GetRenewalReport(ctx)
	if err != nil {
		return nil, fmt.Errorf("renewal report: %w", err)
	}
	return r, nil
}

func (s *Service) GetPlanReport(ctx context.Context) (*PlanReport, error) {
	r, err := s.repo.GetPlanReport(ctx)
	if err != nil {
		return nil, fmt.Errorf("plan report: %w", err)
	}
	return r, nil
}
