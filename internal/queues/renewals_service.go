package queues

import (
	"context"
	"errors"
	"strings"

	"gymcrm/internal/database"
)

var ErrNotLapsable = errors.New("queues: member is already closed or does not exist")

// Renewals builds the queue (FR-19 §4).
func (s *Service) Renewals(ctx context.Context) (*RenewalQueue, error) {
	rows, err := s.repo.Renewals(ctx, RenewalWindowDays)
	if err != nil {
		return nil, err
	}
	beyond, err := s.repo.LapsedBeyondWindow(ctx, RenewalWindowDays)
	if err != nil {
		return nil, err
	}

	lapsed := RenewalGroup{
		Key:      GroupLapsed,
		Label:    "Lapsed — still worth a call",
		Note:     "Expired in the last 30 days and not renewed. The window where somebody usually still comes back.",
		Severity: "urgent",
		Items:    []RenewalItem{},
	}
	today := RenewalGroup{
		Key:      GroupDueToday,
		Label:    "Expires today",
		Note:     "The last day to catch them before it lapses.",
		Severity: "urgent",
		Items:    []RenewalItem{},
	}
	week := RenewalGroup{
		Key:      GroupDueWeek,
		Label:    "Expires this week",
		Note:     "Within seven days. Renewing before expiry is the cheapest retention there is.",
		Severity: "warn",
		Items:    []RenewalItem{},
	}
	month := RenewalGroup{
		Key:      GroupDueMonth,
		Label:    "Expires this month",
		Note:     "Further out. Here so the desk can see what is coming, not so anybody chases it today.",
		Severity: "normal",
		Items:    []RenewalItem{},
	}

	queue := &RenewalQueue{WindowDays: RenewalWindowDays, BeyondWindow: beyond}

	for _, r := range rows {
		item := RenewalItem{
			MemberID:         r.MemberID,
			Member:           r.Member,
			Phone:            r.Phone,
			PlanID:           r.PlanID,
			PlanName:         r.PlanName,
			PlanInPaise:      r.PlanInPaise,
			ExpiryDate:       r.ExpiryDate,
			DaysUntilExpiry:  r.DaysUntilExpiry,
			LastVisitAt:      r.LastVisitAt,
			OwedInPaise:      r.OwedInPaise,
			PreviousRenewals: r.PreviousRenewals,
		}

		var value int64
		if r.PlanInPaise != nil {
			value = *r.PlanInPaise
		}

		queue.TotalCount++
		queue.ValueInPaise += value

		switch {
		case r.DaysUntilExpiry < 0:
			lapsed.Items = append(lapsed.Items, item)
			lapsed.ValueInPaise += value
		case r.DaysUntilExpiry == 0:
			today.Items = append(today.Items, item)
			today.ValueInPaise += value
		case r.DaysUntilExpiry <= 7:
			week.Items = append(week.Items, item)
			week.ValueInPaise += value
		default:
			month.Items = append(month.Items, item)
			month.ValueInPaise += value
		}
	}

	queue.Groups = []RenewalGroup{lapsed, today, week, month}
	return queue, nil
}

// ConfirmLapse records that a member did not come back.
//
// Owner-only, like a write-off, and for the same reason: it is the decision
// that takes somebody out of the queue without money arriving. A reason is
// required — "churned, no reason given" is a row nobody can interpret later.
func (s *Service) ConfirmLapse(ctx context.Context, memberID int64, reason string) error {
	tc := database.MustGetTenant(ctx)
	if !tc.IsOwner() {
		return ErrOwnerOnly
	}

	r := strings.TrimSpace(reason)
	if r == "" {
		return ErrReasonRequired
	}

	return s.repo.ConfirmLapse(ctx, memberID, r)
}
