package queues

import (
	"context"
	"time"

	"gorm.io/gorm"

	"gymcrm/internal/database"
)

type renewalRow struct {
	MemberID         int64
	Member           string
	Phone            string
	PlanID           *int64
	PlanName         *string
	PlanInPaise      *int64
	ExpiryDate       *time.Time
	DaysUntilExpiry  int
	LastVisitAt      *time.Time
	OwedInPaise      int64
	PreviousRenewals int
}

// Renewals returns memberships expiring inside the window.
//
// Excludes statuses that mean the gym already knows how this ended:
// terminated and churned are decisions somebody made, and re-listing them
// would ask the desk to make the same decision twice. Frozen is excluded too —
// a paused membership is not lapsing, it is paused on purpose.
func (r *Repository) Renewals(ctx context.Context, windowDays int) ([]renewalRow, error) {
	tc := database.MustGetTenant(ctx)

	memberName := `TRIM(m.first_name || ' ' || COALESCE(m.last_name, ''))`

	sql := `
		SELECT m.id AS member_id,
		       ` + memberName + ` AS member,
		       COALESCE(m.phone, '') AS phone,
		       m.membership_plan_id AS plan_id,
		       p.name AS plan_name,
		       p.price_in_paise AS plan_in_paise,
		       m.expiry_date,
		       (m.expiry_date - CURRENT_DATE) AS days_until_expiry,
		       att.at   AS last_visit_at,
		       COALESCE(owed.amount, 0) AS owed_in_paise,
		       COALESCE(ren.n, 0)       AS previous_renewals

		  FROM members m
		  LEFT JOIN membership_plans p ON p.id = m.membership_plan_id

		  LEFT JOIN LATERAL (
		      SELECT MAX(a.checked_in_at) AS at
		        FROM attendance a
		       WHERE a.member_id = m.id
		  ) att ON true

		  LEFT JOIN LATERAL (
		      SELECT SUM(o.amount_in_paise) AS amount
		        FROM payments o
		       WHERE o.gym_id = m.gym_id
		         AND o.member_id = m.id
		         AND o.status IN ('pending', 'overdue')
		  ) owed ON true

		  LEFT JOIN LATERAL (
		      SELECT COUNT(*) AS n
		        FROM renewals rn
		       WHERE rn.gym_id = m.gym_id AND rn.member_id = m.id
		  ) ren ON true

		 WHERE m.gym_id = @gym
		   AND m.deleted_at IS NULL
		   AND m.expiry_date IS NOT NULL
		   AND m.status NOT IN ('terminated', 'churned', 'frozen')
		   AND m.expiry_date >= CURRENT_DATE - CAST(@window AS int)
		   AND m.expiry_date <= CURRENT_DATE + CAST(@window AS int)

		 -- Soonest first, so the top of every group is the most urgent thing
		 -- in it. Orders memberships, never staff.
		 ORDER BY m.expiry_date ASC, ` + memberName + ` ASC`

	var rows []renewalRow
	err := r.db.WithContext(ctx).Raw(sql, map[string]interface{}{
		"gym":    tc.GymID(),
		"window": windowDays,
	}).Scan(&rows).Error
	return rows, err
}

// LapsedBeyondWindow counts the people the window leaves out.
//
// Reported rather than dropped. A queue that silently truncates is worse than
// one that admits where its edge is, and this number is the argument for
// widening the window if the gym wants it widened.
func (r *Repository) LapsedBeyondWindow(ctx context.Context, windowDays int) (int, error) {
	tc := database.MustGetTenant(ctx)

	var n int64
	err := r.db.WithContext(ctx).
		Table("members").
		Where(`gym_id = ? AND deleted_at IS NULL AND expiry_date IS NOT NULL
		       AND status NOT IN ('terminated', 'churned', 'frozen')
		       AND expiry_date < CURRENT_DATE - CAST(? AS int)`,
			tc.GymID(), windowDays).
		Count(&n).Error
	return int(n), err
}

// ConfirmLapse records that a member did not come back.
//
// Writes the event and the status together: a churned member with no event
// explaining why is exactly the row somebody queries six months later and
// cannot interpret.
func (r *Repository) ConfirmLapse(ctx context.Context, memberID int64, reason string) error {
	tc := database.MustGetTenant(ctx)

	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		res := tx.Table("members").
			Where(`id = ? AND gym_id = ? AND deleted_at IS NULL
			       AND status NOT IN ('terminated', 'churned')`,
				memberID, tc.GymID()).
			Updates(map[string]interface{}{
				"status":     "churned",
				"updated_at": time.Now(),
			})
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected == 0 {
			return ErrNotLapsable
		}

		return tx.Exec(`
			INSERT INTO membership_events
			    (gym_id, member_id, event_type, reason, effective_date,
			     performed_by_user_id, created_at)
			VALUES (?, ?, 'lapse_confirmed', ?, CURRENT_DATE, ?, NOW())`,
			tc.GymID(), memberID, reason, tc.UserID()).Error
	})
}
