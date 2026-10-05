package referrals

import (
	"context"
	"fmt"
	"strings"
	"time"

	"gymcrm/internal/database"
)

// Service holds referral tracking logic.
//
// Status flow: pending → joined → rewarded, or pending/joined → expired.
// Reward is FREE DAYS added to the referrer's expiry_date — never cash,
// never automatic. Staff explicitly mark a referral joined once the referred
// person actually signs up, then explicitly reward it; nothing here fires
// on its own.
type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

func (s *Service) Create(ctx context.Context, req CreateReferralRequest) (*ReferralResponse, error) {
	if err := validateCreate(req); err != nil {
		return nil, err
	}
	tc := database.MustGetTenant(ctx)

	referrer, err := s.repo.FindMember(ctx, req.ReferrerMemberID)
	if err != nil {
		return nil, fmt.Errorf("create referral: find referrer: %w", err)
	}
	if referrer == nil {
		return nil, ErrReferrerNotFound
	}
	if referrer.Status != "active" {
		return nil, ErrReferrerNotActive
	}

	ref := &Referral{
		GymID:            tc.GymID(),
		ReferrerMemberID: req.ReferrerMemberID,
		ReferredName:     strings.TrimSpace(req.ReferredName),
		ReferredPhone:    strings.TrimSpace(req.ReferredPhone),
		Status:           StatusPending,
		Notes:            optionalText(req.Notes),
		CreatedByUserID:  tc.UserID(),
	}
	if err := s.repo.Create(ctx, ref); err != nil {
		return nil, fmt.Errorf("create referral: %w", err)
	}
	return s.get(ctx, ref.ID)
}

// MarkJoined links a referral to the member the referred person became.
// Does not touch money or days — that's Reward, a separate explicit step.
func (s *Service) MarkJoined(ctx context.Context, id int64, req MarkJoinedRequest) (*ReferralResponse, error) {
	existing, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("mark joined: find: %w", err)
	}
	if existing == nil {
		return nil, ErrReferralNotFound
	}
	if existing.Status != StatusPending {
		return nil, ErrNotPending
	}
	if req.ReferredMemberID <= 0 {
		return nil, fmt.Errorf("referred_member_id is required")
	}

	if err := s.repo.Update(ctx, id, map[string]any{
		"status":             StatusJoined,
		"referred_member_id": req.ReferredMemberID,
	}); err != nil {
		return nil, fmt.Errorf("mark joined: %w", err)
	}
	return s.get(ctx, id)
}

// Reward pays out a joined referral: extends the referrer's expiry_date by
// reward_days and marks the referral rewarded. Requires the referrer still
// be findable — if they've since been terminated, the reward still applies
// to their expiry_date (a terminated member's history shouldn't silently
// erase an earned reward), but a frozen member's reward extends the date
// they'll resume on, same 1:1 meaning a lifecycle freeze extension has.
func (s *Service) Reward(ctx context.Context, id int64, req RewardRequest) (*ReferralResponse, error) {
	if err := validateReward(req); err != nil {
		return nil, err
	}
	existing, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("reward: find: %w", err)
	}
	if existing == nil {
		return nil, ErrReferralNotFound
	}
	if existing.Status == StatusRewarded {
		return nil, ErrAlreadyRewarded
	}
	if existing.Status != StatusJoined {
		return nil, ErrNotJoined
	}

	referrer, err := s.repo.FindMember(ctx, existing.ReferrerMemberID)
	if err != nil {
		return nil, fmt.Errorf("reward: find referrer: %w", err)
	}
	if referrer == nil {
		return nil, ErrReferrerNotFound
	}
	if referrer.ExpiryDate != nil {
		newExpiry := referrer.ExpiryDate.AddDate(0, 0, req.RewardDays)
		if err := s.repo.ExtendMemberExpiry(ctx, referrer.ID, newExpiry); err != nil {
			return nil, fmt.Errorf("reward: extend expiry: %w", err)
		}
	}

	now := time.Now()
	if err := s.repo.Update(ctx, id, map[string]any{
		"status":          StatusRewarded,
		"reward_days":     req.RewardDays,
		"reward_given_at": now,
	}); err != nil {
		return nil, fmt.Errorf("reward: %w", err)
	}
	return s.get(ctx, id)
}

// Expire marks a referral that never converted. Manual only — no background
// job watches for staleness, same discipline as the rest of this codebase.
func (s *Service) Expire(ctx context.Context, id int64) (*ReferralResponse, error) {
	existing, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("expire: find: %w", err)
	}
	if existing == nil {
		return nil, ErrReferralNotFound
	}
	if existing.Status == StatusRewarded {
		return nil, ErrAlreadyRewarded
	}
	if err := s.repo.Update(ctx, id, map[string]any{"status": StatusExpired}); err != nil {
		return nil, fmt.Errorf("expire: %w", err)
	}
	return s.get(ctx, id)
}

func (s *Service) List(ctx context.Context, referrerMemberID *int64) ([]ReferralResponse, error) {
	rows, err := s.repo.List(ctx, referrerMemberID)
	if err != nil {
		return nil, fmt.Errorf("list referrals: %w", err)
	}
	out := make([]ReferralResponse, 0, len(rows))
	for _, r := range rows {
		out = append(out, toResponse(r))
	}
	return out, nil
}

func (s *Service) get(ctx context.Context, id int64) (*ReferralResponse, error) {
	row, err := s.repo.rowByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("get referral: %w", err)
	}
	if row == nil {
		return nil, ErrReferralNotFound
	}
	resp := toResponse(*row)
	return &resp, nil
}

func toResponse(r referralRow) ReferralResponse {
	return ReferralResponse{
		ID: r.ID, ReferrerMemberID: r.ReferrerMemberID, ReferrerName: r.ReferrerName,
		ReferredName: r.ReferredName, ReferredPhone: r.ReferredPhone,
		ReferredMemberID: r.ReferredMemberID, Status: r.Status,
		RewardDays: r.RewardDays, RewardGivenAt: r.RewardGivenAt,
		Notes: r.Notes, CreatedByUserName: r.CreatedByUserName, CreatedAt: r.CreatedAt,
	}
}

func optionalText(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}
