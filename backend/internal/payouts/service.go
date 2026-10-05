package payouts

import (
	"context"
	"fmt"
	"time"

	"gymcrm/internal/database"
)

type Service struct{ repo *Repository }

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

// IST matches the rest of the system: gym-local days, no tzdata in the
// container.
var IST = time.FixedZone("IST", 5*60*60+30*60)

// Compute works out what a trainer earned in a period, without writing.
//
// Every component is derived here and nowhere else, so the preview a person
// approves and the payout that gets stored cannot disagree.
func (s *Service) Compute(
	ctx context.Context, trainerID int64, from, to string,
) (*Preview, []PayoutLine, error) {
	start, end, err := parsePeriod(from, to)
	if err != nil {
		return nil, nil, err
	}

	t, err := s.repo.Trainer(ctx, trainerID)
	if err != nil {
		return nil, nil, err
	}

	out := &Preview{
		TrainerID:   t.ID,
		Trainer:     t.Name,
		PeriodStart: from,
		PeriodEnd:   to,
	}
	var lines []PayoutLine

	// ── Salary ──────────────────────────────────────────────────────────
	//
	// Only for a whole calendar month. Pro-rating a monthly salary across an
	// arbitrary range would produce a number that looks authoritative and is
	// nobody's actual agreement, so the request is refused instead.
	if t.SalaryInPaise != nil && *t.SalaryInPaise > 0 {
		if !isWholeMonth(start, end) {
			return nil, nil, ErrSalaryNeedsMonth
		}
		out.SalaryInPaise = *t.SalaryInPaise
		lines = append(lines, PayoutLine{
			Kind:          KindSalary,
			Description:   "Salary for " + start.Format("January 2006"),
			AmountInPaise: *t.SalaryInPaise,
		})
	}

	// ── Commission on money received ────────────────────────────────────
	if t.CommissionPct != nil && *t.CommissionPct > 0 {
		base, err := s.repo.CommissionBase(ctx, trainerID, from, to)
		if err != nil {
			return nil, nil, fmt.Errorf("payouts: commission: %w", err)
		}
		for _, b := range base {
			// Integer paise, truncated. Never rounded up: a rounding gain
			// repeated monthly is a real overpayment nobody agreed to.
			amount := int64(float64(b.PaidInPaise) * *t.CommissionPct / 100)
			out.CommissionInPaise += amount

			pkgID := b.PackageID
			lines = append(lines, PayoutLine{
				Kind:        KindCommission,
				ReferenceID: &pkgID,
				Description: fmt.Sprintf("%.0f%% of %s — %s (paid %s)",
					*t.CommissionPct, rupees(b.PaidInPaise), b.Member,
					dateOf(b.PaidDate)),
				AmountInPaise: amount,
			})
		}

		// What was sold but not collected. Not paid, but said out loud.
		amount, n, err := s.repo.UncollectedPT(ctx, trainerID)
		if err != nil {
			return nil, nil, fmt.Errorf("payouts: uncollected: %w", err)
		}
		out.UncollectedInPaise = amount
		out.UncollectedCount = n
	}

	// ── Per session delivered ───────────────────────────────────────────
	if t.PerSessionInPaise != nil && *t.PerSessionInPaise > 0 {
		sessions, err := s.repo.SessionsDelivered(ctx, trainerID, from, to)
		if err != nil {
			return nil, nil, fmt.Errorf("payouts: sessions: %w", err)
		}
		for _, sess := range sessions {
			id := sess.AppointmentID
			out.SessionsInPaise += *t.PerSessionInPaise
			lines = append(lines, PayoutLine{
				Kind:        KindSession,
				ReferenceID: &id,
				Description: fmt.Sprintf("Session with %s on %s",
					sess.Member, sess.ScheduledAt.In(IST).Format("2 Jan")),
				AmountInPaise: *t.PerSessionInPaise,
			})
		}
	}

	out.TotalInPaise =
		out.SalaryInPaise + out.CommissionInPaise + out.SessionsInPaise

	exists, err := s.repo.LivePayoutExists(ctx, trainerID, from, to)
	if err != nil {
		return nil, nil, err
	}
	out.AlreadyPaid = exists

	// The breakdown travels with the total, always. A payout figure with no
	// lines behind it is one neither the owner approving it nor the trainer
	// accepting it can check — which is the whole reason the lines exist.
	out.Lines = lines
	if out.Lines == nil {
		out.Lines = []PayoutLine{}
	}

	return out, lines, nil
}

// Preview is Compute with nothing written.
func (s *Service) Preview(
	ctx context.Context, trainerID int64, from, to string,
) (*Preview, error) {
	p, _, err := s.Compute(ctx, trainerID, from, to)
	return p, err
}

// Create stores a draft from the same computation the preview showed.
func (s *Service) Create(
	ctx context.Context, trainerID int64, from, to string,
	adjustment int64, adjustmentReason, notes string,
) (*Payout, error) {
	preview, lines, err := s.Compute(ctx, trainerID, from, to)
	if err != nil {
		return nil, err
	}
	if preview.AlreadyPaid {
		return nil, ErrAlreadyExists
	}
	if preview.TotalInPaise == 0 && adjustment == 0 {
		return nil, ErrNothingToPay
	}

	start, end, _ := parsePeriod(from, to)

	p := &Payout{
		TrainerID:         trainerID,
		Trainer:           preview.Trainer,
		PeriodStart:       start,
		PeriodEnd:         end,
		SalaryInPaise:     preview.SalaryInPaise,
		CommissionInPaise: preview.CommissionInPaise,
		SessionsInPaise:   preview.SessionsInPaise,
		AdjustmentInPaise: adjustment,
		TotalInPaise:      preview.TotalInPaise + adjustment,
		Status:            StatusDraft,
	}
	if adjustmentReason != "" {
		p.AdjustmentReason = &adjustmentReason
	}
	if notes != "" {
		p.Notes = &notes
	}
	if adjustment != 0 {
		lines = append(lines, PayoutLine{
			Kind:          KindAdjustment,
			Description:   adjustmentText(adjustmentReason),
			AmountInPaise: adjustment,
		})
	}

	id, err := s.repo.Create(ctx, p, lines)
	if err != nil {
		return nil, fmt.Errorf("payouts: create: %w", err)
	}
	p.ID = id
	p.Lines = lines
	return p, nil
}

// MarkPaid records that the money left. Owner only: this is the one operation
// here that moves cash out of the gym.
func (s *Service) MarkPaid(
	ctx context.Context, id int64, mode, reference string,
) error {
	tc := database.MustGetTenant(ctx)
	if !tc.IsOwner() {
		return ErrOwnerOnly
	}

	n, err := s.repo.MarkPaid(ctx, id, mode, reference)
	if err != nil {
		return fmt.Errorf("payouts: mark paid: %w", err)
	}
	if n == 0 {
		return ErrNotDraft
	}
	return nil
}

func (s *Service) Cancel(ctx context.Context, id int64) error {
	n, err := s.repo.Cancel(ctx, id)
	if err != nil {
		return fmt.Errorf("payouts: cancel: %w", err)
	}
	if n == 0 {
		return ErrNotDraft
	}
	return nil
}

func (s *Service) List(ctx context.Context, status string) ([]Payout, error) {
	return s.repo.List(ctx, status)
}

func (s *Service) Get(ctx context.Context, id int64) (*Payout, error) {
	all, err := s.repo.List(ctx, "")
	if err != nil {
		return nil, err
	}
	for i := range all {
		if all[i].ID != id {
			continue
		}
		lines, err := s.repo.Lines(ctx, id)
		if err != nil {
			return nil, err
		}
		all[i].Lines = lines
		return &all[i], nil
	}
	return nil, ErrNotDraft
}

// ── helpers ─────────────────────────────────────────────────────────────────

func parsePeriod(from, to string) (time.Time, time.Time, error) {
	start, err := time.ParseInLocation("2006-01-02", from, IST)
	if err != nil {
		return time.Time{}, time.Time{}, ErrBadPeriod
	}
	end, err := time.ParseInLocation("2006-01-02", to, IST)
	if err != nil {
		return time.Time{}, time.Time{}, ErrBadPeriod
	}
	if end.Before(start) {
		return time.Time{}, time.Time{}, ErrBadPeriod
	}
	return start, end, nil
}

// isWholeMonth is true when the period is exactly one calendar month, first
// day to last.
func isWholeMonth(start, end time.Time) bool {
	if start.Day() != 1 {
		return false
	}
	if start.Year() != end.Year() || start.Month() != end.Month() {
		return false
	}
	last := start.AddDate(0, 1, -1)
	return end.Day() == last.Day()
}

func adjustmentText(reason string) string {
	if reason == "" {
		return "Adjustment"
	}
	return "Adjustment — " + reason
}

func dateOf(t *time.Time) string {
	if t == nil {
		return "no date"
	}
	return t.In(IST).Format("2 Jan")
}

func rupees(paise int64) string {
	return fmt.Sprintf("₹%d", paise/100)
}
