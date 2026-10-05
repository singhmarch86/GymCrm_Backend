package recognition

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"gorm.io/gorm"

	"gymcrm/internal/database"
)

var (
	ErrBlankReason    = errors.New("reason cannot be blank")
	ErrBadSignal      = errors.New("signal_type must be 'rhythm' or 'feedback'")
	ErrSignalMismatch = errors.New("signal_type and signal_id must be given together")
	ErrMemberNotHere  = errors.New("that member is not at your branch")
)

type Service struct {
	repo *Repository
	db   *gorm.DB
}

func NewService(repo *Repository, db *gorm.DB) *Service {
	return &Service{repo: repo, db: db}
}

type CreateRequest struct {
	Reason     string `json:"reason"`
	SignalType string `json:"signal_type,omitempty"`
	SignalID   *int64 `json:"signal_id,omitempty"`
}

// Create records one act of recognition. Always a human reason; the signal
// fields are an optional citation, never a computed trigger.
func (s *Service) Create(ctx context.Context, memberID int64, req CreateRequest) (*Row, error) {
	reason := strings.TrimSpace(req.Reason)
	if reason == "" {
		return nil, ErrBlankReason
	}

	signalType := strings.TrimSpace(req.SignalType)
	if signalType != "" && signalType != SignalRhythm && signalType != SignalFeedback {
		return nil, ErrBadSignal
	}
	if (signalType == "") != (req.SignalID == nil) {
		return nil, ErrSignalMismatch
	}

	tc := database.MustGetTenant(ctx)

	var memberExists int64
	s.db.WithContext(ctx).Table("members").
		Where("id = ? AND gym_id = ?", memberID, tc.GymID()).Count(&memberExists)
	if memberExists == 0 {
		return nil, ErrMemberNotHere
	}

	rec := &Recognition{
		GymID: tc.GymID(), MemberID: memberID, Reason: reason,
		CreatedByUserID: tc.UserID(),
	}
	if signalType != "" {
		rec.SignalType = &signalType
		rec.SignalID = req.SignalID
	}
	if err := s.repo.Create(ctx, rec); err != nil {
		return nil, fmt.Errorf("create recognition: %w", err)
	}

	rows, err := s.repo.ByMember(ctx, tc.GymID(), memberID)
	if err != nil || len(rows) == 0 {
		return nil, fmt.Errorf("create recognition: reload: %w", err)
	}
	out := toRow(rows[0])
	return &out, nil
}

func (s *Service) ByMember(ctx context.Context, memberID int64) ([]Row, error) {
	tc := database.MustGetTenant(ctx)
	rows, err := s.repo.ByMember(ctx, tc.GymID(), memberID)
	if err != nil {
		return nil, fmt.Errorf("member recognitions: %w", err)
	}
	out := make([]Row, 0, len(rows))
	for _, r := range rows {
		out = append(out, toRow(r))
	}
	return out, nil
}

func toRow(r row) Row {
	return Row{
		ID: r.ID, MemberID: r.MemberID, Reason: r.Reason,
		SignalType: r.SignalType, SignalID: r.SignalID,
		CreatedByName: r.CreatedByName, CreatedAt: r.CreatedAt,
	}
}
