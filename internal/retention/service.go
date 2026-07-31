package retention

import (
	"context"
	"fmt"
	"strings"
)

// Policy thresholds.
//
// Hardcoded for now rather than per-gym settings: the right values are not
// obvious yet, and guessing at a settings schema before anyone has seen real
// output would likely need a migration to correct. Promote these to gym config
// once actual usage says what they should be.
const (
	expiringSoonDays = 3  // "renewal due in N days" warning
	inactiveWarnDays = 7  // drifting
	inactiveRiskDays = 14 // churn risk
	// Absences beyond this are treated as churn risk rather than a new tier, so
	// the two inactivity bands stay mutually exclusive.
	inactiveRiskCeiling = 0 // 0 = no upper bound
)

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// ScanResult reports what a scan did, so the UI can say something specific
// instead of just "done".
type ScanResult struct {
	Raised   int64 `json:"raised"`   // new alerts created
	Resolved int64 `json:"resolved"` // alerts auto-closed because the issue passed
	Skipped  int64 `json:"skipped"`  // candidates that already had an open alert
}

// Scan evaluates every retention policy and reconciles the alert list.
//
// Order matters: auto-resolve runs FIRST. A member who renewed yesterday still
// has an open "expiring today" alert; closing it before re-scanning means the
// dedup index no longer blocks a fresh, correct alert if they somehow qualify
// again. Scanning first would leave the stale alert holding the unique slot.
//
// Safe to run repeatedly — the partial unique index makes inserts idempotent.
func (s *Service) Scan(ctx context.Context) (*ScanResult, error) {
	result := &ScanResult{}

	resolved, err := s.repo.AutoResolve(ctx)
	if err != nil {
		return nil, fmt.Errorf("retention scan: auto-resolve: %w", err)
	}
	result.Resolved = resolved

	var candidates int64
	var pending []NewAlert

	// ── Expiring in N days ────────────────────────────────────────────────
	rows, err := s.repo.FindExpiringInDays(ctx, expiringSoonDays)
	if err != nil {
		return nil, fmt.Errorf("retention scan: expiring soon: %w", err)
	}
	for _, c := range rows {
		pending = append(pending, NewAlert{
			MemberID:  c.MemberID,
			AlertType: AlertExpiringIn3Days,
			Severity:  SeverityLow,
			Message: fmt.Sprintf(
				"Hi %s, your gym membership expires in %d days. Renew now to keep your streak going!",
				firstName(c.MemberName), c.DaysValue,
			),
		})
	}
	candidates += int64(len(rows))

	// ── Expiring today ────────────────────────────────────────────────────
	rows, err = s.repo.FindExpiringInDays(ctx, 0)
	if err != nil {
		return nil, fmt.Errorf("retention scan: expiring today: %w", err)
	}
	for _, c := range rows {
		pending = append(pending, NewAlert{
			MemberID:  c.MemberID,
			AlertType: AlertExpiringToday,
			Severity:  SeverityHigh,
			Message: fmt.Sprintf(
				"Hi %s, your membership expires today. Renew today to avoid a break in your training.",
				firstName(c.MemberName),
			),
		})
	}
	candidates += int64(len(rows))

	// ── Expired, no renewal ───────────────────────────────────────────────
	rows, err = s.repo.FindExpiredWithoutRenewal(ctx)
	if err != nil {
		return nil, fmt.Errorf("retention scan: expired: %w", err)
	}
	for _, c := range rows {
		pending = append(pending, NewAlert{
			MemberID:  c.MemberID,
			AlertType: AlertExpiredNoRenewal,
			Severity:  SeverityHigh,
			Message: fmt.Sprintf(
				"Hi %s, your membership lapsed %s ago. We'd love to have you back — reply to renew.",
				firstName(c.MemberName), pluralDays(c.DaysValue),
			),
		})
	}
	candidates += int64(len(rows))

	// ── Inactive 7–13 days ────────────────────────────────────────────────
	// Bounded below the churn tier so a member absent 20 days appears once, as
	// churn risk, not twice.
	rows, err = s.repo.FindInactive(ctx, inactiveWarnDays, inactiveRiskDays)
	if err != nil {
		return nil, fmt.Errorf("retention scan: inactive 1 week: %w", err)
	}
	for _, c := range rows {
		pending = append(pending, NewAlert{
			MemberID:  c.MemberID,
			AlertType: AlertInactiveOneWeek,
			Severity:  SeverityLow,
			Message: fmt.Sprintf(
				"Hi %s, we haven't seen you in %s. Everything okay? Your membership is still active — come train with us!",
				firstName(c.MemberName), pluralDays(c.DaysValue),
			),
		})
	}
	candidates += int64(len(rows))

	// ── Inactive 14+ days ─────────────────────────────────────────────────
	rows, err = s.repo.FindInactive(ctx, inactiveRiskDays, inactiveRiskCeiling)
	if err != nil {
		return nil, fmt.Errorf("retention scan: inactive 2 weeks: %w", err)
	}
	for _, c := range rows {
		// A paying member who has vanished for a fortnight is the single
		// strongest churn signal there is — escalate past two weeks.
		severity := SeverityMedium
		if c.DaysValue >= 21 {
			severity = SeverityHigh
		}
		pending = append(pending, NewAlert{
			MemberID:  c.MemberID,
			AlertType: AlertInactiveTwoWeeks,
			Severity:  severity,
			Message: fmt.Sprintf(
				"Hi %s, it's been %s since your last visit and we'd hate to lose you. Can we help you get back on track?",
				firstName(c.MemberName), pluralDays(c.DaysValue),
			),
		})
	}
	candidates += int64(len(rows))

	raised, err := s.repo.InsertAlerts(ctx, pending)
	if err != nil {
		return nil, fmt.Errorf("retention scan: insert: %w", err)
	}
	result.Raised = raised
	// Anything matched but not inserted was already an open alert — worth
	// reporting so a scan that raises 0 reads as "nothing new" rather than
	// "nothing wrong".
	result.Skipped = candidates - raised

	return result, nil
}

func (s *Service) ListAlerts(ctx context.Context, severity string, includeResolved bool) ([]AlertRow, error) {
	if severity != "" && !IsValidSeverity(severity) {
		return nil, ErrInvalidSeverity
	}
	out, err := s.repo.ListAlerts(ctx, severity, includeResolved)
	if err != nil {
		return nil, fmt.Errorf("list alerts: %w", err)
	}
	return out, nil
}

// ResolveAlert marks an alert handled by the current user. note is optional —
// see the repository for why it is not forced.
func (s *Service) ResolveAlert(ctx context.Context, id int64, note *string) error {
	if note != nil {
		trimmed := strings.TrimSpace(*note)
		if trimmed == "" {
			note = nil
		} else {
			note = &trimmed
		}
	}
	affected, err := s.repo.ResolveAlert(ctx, id, note)
	if err != nil {
		return fmt.Errorf("resolve alert: %w", err)
	}
	if affected == 0 {
		// Either it does not exist, belongs to another gym, or was already
		// closed — all indistinguishable to the caller, and all "not found".
		return ErrAlertNotFound
	}
	return nil
}

// Summary backs the dashboard badge and the screen header.
type Summary struct {
	Counts     map[string]int64 `json:"counts"`
	Total      int64            `json:"total"`
	LastScanAt *string          `json:"last_scan_at,omitempty"`
}

func (s *Service) GetSummary(ctx context.Context) (*Summary, error) {
	counts, err := s.repo.CountsBySeverity(ctx)
	if err != nil {
		return nil, fmt.Errorf("retention summary: %w", err)
	}
	lastScan, err := s.repo.LastScanAt(ctx)
	if err != nil {
		return nil, fmt.Errorf("retention summary: last scan: %w", err)
	}

	var total int64
	for _, v := range counts {
		total += v
	}

	return &Summary{Counts: counts, Total: total, LastScanAt: lastScan}, nil
}

// StaffActivitySince reports who has been clearing the at-risk list, so an
// owner can see the work actually happening rather than only its result.
func (s *Service) StaffActivitySince(ctx context.Context, days int) ([]StaffActivity, error) {
	if days <= 0 {
		days = 7
	}
	// 5 recent items per person: enough to show what the work was, few
	// enough that the panel stays a summary rather than a full log.
	out, err := s.repo.ResolvedByStaff(ctx, days, 5)
	if err != nil {
		return nil, fmt.Errorf("staff activity: %w", err)
	}
	return out, nil
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

// firstName keeps the generated messages personal without sounding like a form
// letter ("Hi Rahul" reads better than "Hi Rahul Kumar").
func firstName(full string) string {
	for i, r := range full {
		if r == ' ' {
			return full[:i]
		}
	}
	if full == "" {
		return "there"
	}
	return full
}

func pluralDays(d int) string {
	if d == 1 {
		return "1 day"
	}
	if d >= 14 {
		weeks := d / 7
		if weeks == 1 {
			return "over a week"
		}
		return fmt.Sprintf("over %d weeks", weeks)
	}
	return fmt.Sprintf("%d days", d)
}
