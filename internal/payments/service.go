package payments

import (
	"context"
	"fmt"
	"time"

	"gymcrm/internal/shared/pagination"
)

// Service contains all payments business logic.
// CollectPayment is the only write path in Sprint 4 — it delegates the
// actual atomic work to Repository.CollectPayment (a single DB transaction).
// This service layer's job is request→input translation and error mapping,
// not orchestration — the orchestration lives in the repository precisely
// because it must run inside one transaction. See repository.go for the
// full explanation of why that's the case in this package.
type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// ─── Collect payment ──────────────────────────────────────────────────────────

func (s *Service) CollectPayment(ctx context.Context, req CollectPaymentRequest) (*PaymentResponse, error) {
	paidDate := time.Now().UTC().Truncate(24 * time.Hour)
	if req.PaymentDate != "" {
		if t, err := time.Parse(dateLayout, req.PaymentDate); err == nil {
			paidDate = t
		}
	}

	result, err := s.repo.CollectPayment(ctx, CollectPaymentInput{
		MemberID:        req.MemberID,
		PlanID:          req.PlanID,
		AmountInPaise:   req.AmountInPaise,
		PaymentMode:     PaymentMode(req.PaymentMode),
		PaidDate:        paidDate,
		ReferenceNumber: req.ReferenceNumber,
		Notes:           req.Notes,
	})
	if err != nil {
		return nil, fmt.Errorf("collect payment: %w", err)
	}

	// Re-fetch with joins for a fully denormalised response — the
	// transaction result has the raw rows but not member name/phone/plan
	// name, which only the joined query resolves.
	created, err := s.repo.FindByID(ctx, result.Payment.ID)
	if err != nil || created == nil {
		return nil, fmt.Errorf("collect payment: fetch created: %w", err)
	}

	resp := ToResponse(created, time.Now().UTC())
	return &resp, nil
}

// ─── Read ─────────────────────────────────────────────────────────────────────

func (s *Service) GetPayment(ctx context.Context, id int64) (*PaymentResponse, error) {
	payment, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("get payment: %w", err)
	}
	if payment == nil {
		return nil, ErrPaymentNotFound
	}
	resp := ToResponse(payment, time.Now().UTC())
	return &resp, nil
}

func (s *Service) ListPayments(ctx context.Context, req ListPaymentsRequest) ([]PaymentResponse, int64, error) {
	payments, total, err := s.repo.List(ctx, req)
	if err != nil {
		return nil, 0, fmt.Errorf("list payments: %w", err)
	}

	now := time.Now().UTC()
	all := ToResponseList(payments, now)

	// "overdue" is computed, not stored — filter in Go after the status has
	// been resolved by ToResponse. See dto.go's effectiveStatus.
	if req.Status == "overdue" {
		filtered := make([]PaymentResponse, 0, len(all))
		for _, p := range all {
			if p.Status == string(PaymentStatusOverdue) {
				filtered = append(filtered, p)
			}
		}
		return filtered, int64(len(filtered)), nil
	}

	return all, total, nil
}

func (s *Service) GetMemberPayments(ctx context.Context, memberID int64, p pagination.Params) ([]PaymentResponse, int64, error) {
	exists, err := s.repo.MemberExists(ctx, memberID)
	if err != nil {
		return nil, 0, fmt.Errorf("member payments: check member: %w", err)
	}
	if !exists {
		return nil, 0, ErrMemberNotFound
	}

	payments, total, err := s.repo.FindByMember(ctx, memberID, p)
	if err != nil {
		return nil, 0, fmt.Errorf("member payments: %w", err)
	}
	return ToResponseList(payments, time.Now().UTC()), total, nil
}

// ─── Revenue summary ──────────────────────────────────────────────────────────

func (s *Service) GetRevenueSummary(ctx context.Context) (*RevenueSummaryResponse, error) {
	summary, err := s.repo.GetRevenueSummary(ctx)
	if err != nil {
		return nil, fmt.Errorf("revenue summary: %w", err)
	}
	return &RevenueSummaryResponse{
		TodayRevenueInPaise: summary.TodayRevenueInPaise,
		MonthRevenueInPaise: summary.MonthRevenueInPaise,
		PendingPayments:     summary.PendingPayments,
		CollectedCount:      summary.CollectedCount,
	}, nil
}
