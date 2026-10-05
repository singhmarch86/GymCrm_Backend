package ptreport

import (
	"context"
	"fmt"

	"gymcrm/internal/database"
	"gymcrm/internal/ptfeedback"
)

type Service struct {
	repo        *Repository
	feedbackSvc *ptfeedback.Service
}

func NewService(repo *Repository, feedbackSvc *ptfeedback.Service) *Service {
	return &Service{repo: repo, feedbackSvc: feedbackSvc}
}

// Member answers "what does this member's PT picture look like": packages
// bought and remaining, feedback either direction, and their attendance
// signal, cited as-is rather than recomputed here.
func (s *Service) Member(ctx context.Context, memberID int64) (*MemberReport, error) {
	tc := database.MustGetTenant(ctx)

	packages, err := s.repo.MemberPackages(ctx, tc.GymID(), memberID)
	if err != nil {
		return nil, fmt.Errorf("member pt report: packages: %w", err)
	}

	feedback, err := s.feedbackSvc.ByMember(ctx, memberID)
	if err != nil {
		return nil, fmt.Errorf("member pt report: feedback: %w", err)
	}

	rhythm, err := s.repo.RhythmSummary(ctx, tc.GymID(), memberID)
	if err != nil {
		return nil, fmt.Errorf("member pt report: rhythm: %w", err)
	}

	return &MemberReport{
		MemberID: memberID,
		Packages: packages,
		Feedback: toFeedbackRows(feedback),
		Rhythm:   rhythm,
	}, nil
}

// Trainer answers the same question from the other side: sessions actually
// delivered, feedback given or received, who they currently work with, and
// what they were last paid — a citation of payouts, not a recomputation.
func (s *Service) Trainer(ctx context.Context, trainerID int64) (*TrainerReport, error) {
	tc := database.MustGetTenant(ctx)

	completed, err := s.repo.SessionsCompleted(ctx, tc.GymID(), trainerID)
	if err != nil {
		return nil, fmt.Errorf("trainer pt report: sessions: %w", err)
	}

	feedback, err := s.feedbackSvc.ByTrainer(ctx, trainerID)
	if err != nil {
		return nil, fmt.Errorf("trainer pt report: feedback: %w", err)
	}

	members, err := s.repo.AssignedMembers(ctx, tc.GymID(), trainerID)
	if err != nil {
		return nil, fmt.Errorf("trainer pt report: members: %w", err)
	}

	out := &TrainerReport{
		TrainerID:         trainerID,
		SessionsCompleted: completed,
		Feedback:          toFeedbackRows(feedback),
		AssignedMembers:   members,
	}

	payout, err := s.repo.LastPayout(ctx, tc.GymID(), trainerID)
	if err != nil {
		return nil, fmt.Errorf("trainer pt report: payout: %w", err)
	}
	if payout != nil {
		out.LastPayoutInPaise = &payout.TotalInPaise
		out.LastPayoutPeriodTo = &payout.PeriodEnd
	}

	return out, nil
}

func toFeedbackRows(rows []ptfeedback.Row) []FeedbackRow {
	out := make([]FeedbackRow, 0, len(rows))
	for _, r := range rows {
		out = append(out, FeedbackRow{
			ID: r.ID, AuthorRole: r.AuthorRole, Note: r.Note, CreatedAt: r.CreatedAt,
		})
	}
	return out
}
