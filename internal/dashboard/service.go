package dashboard

import "context"

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{
		repo: repo,
	}
}

func (s *Service) GetDashboard(ctx context.Context) (*DashboardResponse, error) {
	return s.repo.GetDashboard(ctx)
}