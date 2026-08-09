package counter

import (
	"context"
	"time"
)

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

// Result is what the desk gets back. PromptID is set only when the prompt was
// logged as shown, and is what "mark acted" refers to.
type Result struct {
	Prompt   *Prompt `json:"prompt,omitempty"`
	PromptID *int64  `json:"prompt_id,omitempty"`
}

// ForCheckIn decides the prompt and records that it was shown.
//
// Called from the check-in path, so the desk gets the member's context in the
// same response as the check-in itself — no second round trip while somebody
// is standing at the counter.
func (s *Service) ForCheckIn(ctx context.Context, memberID, userID int64) (*Result, error) {
	c, err := s.repo.LoadContext(ctx, memberID, time.Now())
	if err != nil {
		return nil, err
	}
	p := Decide(c)
	if p.IsEmpty() {
		// The normal outcome (FR-11 §2). Nothing shown, nothing logged, no
		// cooldown burnt.
		return &Result{}, nil
	}

	id, err := s.repo.LogShown(ctx, memberID, p, userID)
	if err != nil {
		return nil, err
	}
	return &Result{Prompt: &p, PromptID: &id}, nil
}

// Peek returns the same prompt without logging it.
//
// Browsing a member's record must not burn their cooldown, or looking somebody
// up twice would silence the prompt for a week (FR-11 §7).
func (s *Service) Peek(ctx context.Context, memberID int64) (*Result, error) {
	c, err := s.repo.LoadContext(ctx, memberID, time.Now())
	if err != nil {
		return nil, err
	}
	p := Decide(c)
	if p.IsEmpty() {
		return &Result{}, nil
	}
	return &Result{Prompt: &p}, nil
}

func (s *Service) MarkActed(ctx context.Context, promptID int64, note string) (bool, error) {
	n, err := s.repo.MarkActed(ctx, promptID, note)
	return n > 0, err
}

func (s *Service) Effectiveness(ctx context.Context, days int) ([]EffectivenessRow, error) {
	if days <= 0 || days > 365 {
		days = 30
	}
	rows, err := s.repo.Effectiveness(ctx, days)
	if err != nil {
		return nil, err
	}
	if rows == nil {
		rows = []EffectivenessRow{}
	}
	return rows, nil
}
