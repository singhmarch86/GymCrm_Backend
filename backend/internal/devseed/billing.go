package devseed

import (
	"fmt"
	"time"

	"gymcrm/internal/payments"
	"gymcrm/internal/renewals"
)

var paymentModes = []payments.PaymentMode{
	payments.PaymentModeCash,
	payments.PaymentModeUPI,
	payments.PaymentModeCreditCard,
	payments.PaymentModeDebitCard,
	payments.PaymentModeBankTransfer,
}

// seedBilling writes one paid payment + renewal per completed cycle in each
// member's CycleStarts history, plus a pending due for members who are
// currently expiring soon or already expired (PRD: "Generate pending dues
// for expiring members").
//
// This intentionally re-implements payments.Repository.CollectPayment's
// three-step shape (payment first, then renewal, then patch
// renewals.payment_id) rather than calling that method directly — it hard
// -requires a request-scoped database.TenantContext via
// database.MustGetTenant, which doesn't exist at startup.
func (s *seeder) seedBilling() error {
	for i := range s.members {
		m := &s.members[i]
		d := m.Plan.DurationDays

		for k, cycleStart := range m.CycleStarts {
			cycleEnd := cycleStart.AddDate(0, 0, d)

			var oldExpiry *time.Time
			if k > 0 {
				oldExpiry = timePtr(cycleStart) // previous cycle's end == this cycle's start (no gap)
			}

			mode := pick(s.rng, paymentModes)
			payment := payments.Payment{
				GymID:             s.gymID,
				MemberID:          m.ID,
				PlanID:            int64Ptr(m.Plan.ID),
				AmountInPaise:     m.Plan.PriceInPaise,
				Status:            payments.PaymentStatusPaid,
				PaymentMode:       &mode,
				PaidDate:          timePtr(cycleStart),
				CollectedByUserID: int64Ptr(s.deskUser()),
			}
			if err := s.tx.Create(&payment).Error; err != nil {
				return fmt.Errorf("member %d cycle %d payment: %w", m.ID, k, err)
			}
			s.paymentCount++

			renewal := renewals.Renewal{
				GymID:             s.gymID,
				MemberID:          m.ID,
				PlanID:            m.Plan.ID,
				AmountPaidInPaise: m.Plan.PriceInPaise,
				OldExpiryDate:     oldExpiry,
				NewExpiryDate:     cycleEnd,
				RenewalDate:       cycleStart,
				RenewedByUserID:   s.ownerUserID,
			}
			if err := s.tx.Create(&renewal).Error; err != nil {
				return fmt.Errorf("member %d cycle %d renewal: %w", m.ID, k, err)
			}
			s.renewalCount++

			if err := s.tx.Table("renewals").
				Where("id = ?", renewal.ID).
				Update("payment_id", payment.ID).Error; err != nil {
				return fmt.Errorf("member %d cycle %d link payment: %w", m.ID, k, err)
			}
		}

		if m.Segment == segExpiringSoon || m.Segment == segExpired {
			due := payments.Payment{
				GymID:         s.gymID,
				MemberID:      m.ID,
				PlanID:        int64Ptr(m.Plan.ID),
				AmountInPaise: m.Plan.PriceInPaise,
				Status:        payments.PaymentStatusPending,
				DueDate:       m.ExpiryDate,
			}
			if err := s.tx.Create(&due).Error; err != nil {
				return fmt.Errorf("member %d pending due: %w", m.ID, err)
			}
			s.paymentCount++
		}
	}
	return nil
}
