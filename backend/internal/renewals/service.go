package renewals

import (
	"context"
	"fmt"
	"time"

	"gymcrm/internal/database"
	"gymcrm/internal/shared/pagination"
)

// Service contains all renewal business logic.
// Critical invariant: every renewal is created inside a logical transaction —
// the renewal record is inserted AND the member's expiry_date is updated together.
// If either fails, neither should persist. In V1 we handle this sequentially
// and accept the rare inconsistency risk; V2 should wrap in a DB transaction.
type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// ─── Create ───────────────────────────────────────────────────────────────────

// CreateRenewal is the core business operation.
// Steps:
//  1. Validate member exists in this gym
//  2. Validate plan exists, is active, in this gym
//  3. Calculate new expiry: max(member.expiry_date, today) + plan.duration_days
//  4. Insert renewal record (audit trail)
//  5. Update member.expiry_date + status = active
func (s *Service) CreateRenewal(ctx context.Context, req CreateRenewalRequest) (*RenewalResponse, error) {
	tc := database.MustGetTenant(ctx)

	// Step 1: validate member
	member, err := s.repo.FindMemberForRenewal(ctx, req.MemberID)
	if err != nil {
		return nil, fmt.Errorf("create renewal: find member: %w", err)
	}
	if member == nil {
		return nil, ErrMemberNotFound
	}

	// Step 2: validate plan
	plan, err := s.repo.FindPlanForRenewal(ctx, req.PlanID)
	if err != nil {
		return nil, fmt.Errorf("create renewal: find plan: %w", err)
	}
	if plan == nil {
		return nil, ErrPlanNotFound
	}
	if !plan.IsActive {
		return nil, ErrPlanInactive
	}

	// Step 3: expiry calculation
	// baseDate = max(member.expiry_date, today)
	// newExpiry = baseDate + plan.duration_days
	today := time.Now().UTC().Truncate(24 * time.Hour)
	var baseDate time.Time
	if member.ExpiryDate == nil || member.ExpiryDate.Before(today) {
		baseDate = today
	} else {
		baseDate = *member.ExpiryDate
	}
	newExpiry := baseDate.AddDate(0, 0, plan.DurationDays)

	// Step 4: resolve renewal_date
	renewalDate := today
	if req.RenewalDate != "" {
		if t, err := time.Parse(dateLayout, req.RenewalDate); err == nil {
			renewalDate = t
		}
	}

	// Step 5: build renewal record
	renewal := &Renewal{
		GymID:             tc.GymID(),
		MemberID:          req.MemberID,
		PlanID:            req.PlanID,
		AmountPaidInPaise: req.AmountPaidInPaise,
		OldExpiryDate:     member.ExpiryDate, // snapshot before change — nil for first renewal
		NewExpiryDate:     newExpiry,
		RenewalDate:       renewalDate,
		RenewedByUserID:   tc.UserID(),
	}
	if req.Notes != "" {
		renewal.Notes = &req.Notes
	}

	// Step 6: persist renewal record
	if err := s.repo.Create(ctx, renewal); err != nil {
		return nil, fmt.Errorf("create renewal: insert record: %w", err)
	}

	// Step 7: update member expiry — must happen after renewal insert
	// If this fails, we have an orphaned renewal record.
	// V2: wrap steps 6+7 in a DB transaction.
	if err := s.repo.UpdateMemberExpiry(ctx, req.MemberID, newExpiry); err != nil {
		return nil, fmt.Errorf("create renewal: update member expiry: %w", err)
	}

	// Fetch with joined names for response
	created, err := s.repo.FindByID(ctx, renewal.ID)
	if err != nil || created == nil {
		return nil, fmt.Errorf("create renewal: fetch created: %w", err)
	}

	resp := created.ToResponse()
	return &resp, nil
}

// ─── Read ─────────────────────────────────────────────────────────────────────

func (s *Service) GetRenewal(ctx context.Context, id int64) (*RenewalResponse, error) {
	renewal, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("get renewal: %w", err)
	}
	if renewal == nil {
		return nil, ErrRenewalNotFound
	}
	resp := renewal.ToResponse()
	return &resp, nil
}

func (s *Service) ListRenewals(ctx context.Context, req ListRenewalsRequest) ([]RenewalResponse, int64, error) {
	renewals, total, err := s.repo.List(ctx, req)
	if err != nil {
		return nil, 0, fmt.Errorf("list renewals: %w", err)
	}
	return ToResponseList(renewals), total, nil
}

func (s *Service) GetMemberRenewals(ctx context.Context, memberID int64, p pagination.Params) ([]RenewalResponse, int64, error) {
	// Validate member belongs to this gym before listing
	member, err := s.repo.FindMemberForRenewal(ctx, memberID)
	if err != nil {
		return nil, 0, fmt.Errorf("member renewals: find member: %w", err)
	}
	if member == nil {
		return nil, 0, ErrMemberNotFound
	}

	renewals, total, err := s.repo.FindByMember(ctx, memberID, p)
	if err != nil {
		return nil, 0, fmt.Errorf("member renewals: %w", err)
	}
	return ToResponseList(renewals), total, nil
}

func (s *Service) GetRecentRenewals(ctx context.Context, limit int) ([]RenewalResponse, error) {
	renewals, err := s.repo.FindRecent(ctx, limit)
	if err != nil {
		return nil, fmt.Errorf("recent renewals: %w", err)
	}
	return ToResponseList(renewals), nil
}
