package queues

import (
	"context"
	"time"

	"gymcrm/internal/database"
)

type leakRow struct {
	MemberID     int64
	Member       string
	Phone        string
	TrainerID    *int64
	Trainer      *string
	PackageID    *int64
	Count        int
	ValueInPaise int64
	Since        *time.Time
	Extra        string
}

// OversoldPT finds packages that delivered more sessions than were bought.
//
// Counts appointments that were not cancelled: a booking somebody called off
// consumed nothing, and treating it as delivered would invent a loss.
//
// Valued at the package's own per-session rate — amount paid divided by
// sessions bought — because that is the only price this member ever agreed
// to. Using a list rate would overstate a discounted package.
func (r *Repository) OversoldPT(ctx context.Context) ([]leakRow, error) {
	tc := database.MustGetTenant(ctx)

	// Sessions are ranked by date, and everything past the package's limit is
	// an overage. Ranking rather than counting is what lets "since" name the
	// first session that went over — counting alone would report the
	// package's first session, which is a date on which nothing was wrong.
	var rows []leakRow
	err := r.db.WithContext(ctx).Raw(`
		WITH ranked AS (
		    SELECT a.pt_package_id,
		           a.scheduled_at,
		           ROW_NUMBER() OVER (
		               PARTITION BY a.pt_package_id
		               ORDER BY a.scheduled_at ASC, a.id ASC
		           ) AS seq
		      FROM pt_appointments a
		     WHERE a.gym_id = @gym
		       AND a.status <> 'cancelled'
		)
		SELECT p.member_id,
		       TRIM(m.first_name || ' ' || COALESCE(m.last_name, '')) AS member,
		       COALESCE(m.phone, '') AS phone,
		       p.trainer_id,
		       TRIM(t.first_name || ' ' || COALESCE(t.last_name, '')) AS trainer,
		       p.id AS package_id,
		       over.n AS count,
		       -- Integer division on paise: the per-session rate this member
		       -- actually paid, times the overage. Never rounded up.
		       ((p.amount_in_paise / p.total_sessions) * over.n)
		           AS value_in_paise,
		       over.first_over AS since,
		       p.package_name AS extra
		  FROM pt_packages p
		  JOIN members m  ON m.id = p.member_id AND m.deleted_at IS NULL
		  JOIN trainers t ON t.id = p.trainer_id
		  JOIN LATERAL (
		      SELECT COUNT(*) AS n, MIN(r.scheduled_at) AS first_over
		        FROM ranked r
		       WHERE r.pt_package_id = p.id
		         AND r.seq > p.total_sessions
		  ) over ON true
		 WHERE p.gym_id = @gym
		   AND p.total_sessions > 0
		   AND over.n > 0
		 ORDER BY value_in_paise DESC, member ASC`,
		map[string]interface{}{"gym": tc.GymID()}).Scan(&rows).Error
	return rows, err
}

// SessionDrift finds packages whose own counter disagrees with its bookings.
//
// Carries no rupee value on purpose. A drifted counter is not a loss by
// itself — it is how a loss stays hidden, because the counter stops at the
// limit while sessions keep being booked against it.
func (r *Repository) SessionDrift(ctx context.Context) ([]leakRow, error) {
	tc := database.MustGetTenant(ctx)

	var rows []leakRow
	err := r.db.WithContext(ctx).Raw(`
		SELECT p.member_id,
		       TRIM(m.first_name || ' ' || COALESCE(m.last_name, '')) AS member,
		       COALESCE(m.phone, '') AS phone,
		       p.trainer_id,
		       TRIM(t.first_name || ' ' || COALESCE(t.last_name, '')) AS trainer,
		       p.id AS package_id,
		       ABS(held.n - p.sessions_used) AS count,
		       0::bigint AS value_in_paise,
		       NULL::timestamptz AS since,
		       p.package_name AS extra
		  FROM pt_packages p
		  JOIN members m  ON m.id = p.member_id AND m.deleted_at IS NULL
		  JOIN trainers t ON t.id = p.trainer_id
		  JOIN LATERAL (
		      SELECT COUNT(*) AS n
		        FROM pt_appointments a
		       WHERE a.pt_package_id = p.id
		         AND a.status = 'completed'
		  ) held ON true
		 WHERE p.gym_id = @gym
		   AND held.n <> p.sessions_used
		 ORDER BY ABS(held.n - p.sessions_used) DESC, member ASC`,
		map[string]interface{}{"gym": tc.GymID()}).Scan(&rows).Error
	return rows, err
}

// TrainingAfterExpiry finds members who kept coming after their membership ran
// out.
//
// Frozen members are excluded — a paused membership is meant to stop, and its
// expiry date is not the line that matters. Terminated and churned are
// excluded too: the gym already decided how those ended.
//
// Valued at the member's own plan price pro-rated per day, which is a
// deliberate under-estimate of a walk-in rate. Overstating a leak invites the
// owner to accuse somebody.
func (r *Repository) TrainingAfterExpiry(ctx context.Context) ([]leakRow, error) {
	tc := database.MustGetTenant(ctx)

	var rows []leakRow
	err := r.db.WithContext(ctx).Raw(`
		SELECT m.id AS member_id,
		       TRIM(m.first_name || ' ' || COALESCE(m.last_name, '')) AS member,
		       COALESCE(m.phone, '') AS phone,
		       NULL::bigint AS trainer_id,
		       NULL::varchar AS trainer,
		       NULL::bigint AS package_id,
		       v.n AS count,
		       COALESCE(
		           (pl.price_in_paise / NULLIF(pl.duration_days, 0)) * v.n, 0
		       ) AS value_in_paise,
		       v.first_visit AS since,
		       '' AS extra
		  FROM members m
		  LEFT JOIN membership_plans pl ON pl.id = m.membership_plan_id
		  JOIN LATERAL (
		      SELECT COUNT(*) AS n, MIN(a.checked_in_at) AS first_visit
		        FROM attendance a
		       WHERE a.member_id = m.id
		         AND a.checked_in_at::date > m.expiry_date
		  ) v ON true
		 WHERE m.gym_id = @gym
		   AND m.deleted_at IS NULL
		   AND m.expiry_date IS NOT NULL
		   AND m.status NOT IN ('frozen', 'terminated', 'churned')
		   AND v.n > 0
		 ORDER BY value_in_paise DESC, member ASC`,
		map[string]interface{}{"gym": tc.GymID()}).Scan(&rows).Error
	return rows, err
}
