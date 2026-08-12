package queues

import (
	"context"
	"time"

	"gymcrm/internal/database"
	"gymcrm/internal/staffwork"
)

type expectedRow struct {
	Kind          string
	MemberID      int64
	Member        string
	Phone         string
	AmountInPaise int64
	Date          *time.Time
	PaymentID     *int64
	PlanName      *string
	LastVisitAt   *time.Time
	OwedInPaise   int64
}

type expectedTotals struct {
	RaisedCount     int
	RaisedInPaise   int64
	ExpiringCount   int
	ExpiringInPaise int64
}

// memberName matches the form used across the queues package, so the same
// person reads the same way in every list.
const expectedMemberName = `TRIM(m.first_name || ' ' || COALESCE(m.last_name, ''))`

// Two predicates that decide who counts, written once because the totals query
// and the list query must never disagree about them.
const (
	// A due the gym wrote down. Written-off is excluded: the decision not to
	// chase it has been made, and expecting money the gym gave up on is the
	// kind of number that quietly inflates a forecast.
	raisedWhere = `p.gym_id = @gym
	               AND p.status IN ('pending', 'overdue')
	               AND p.due_date BETWEEN CAST(@from AS date) AND CAST(@to AS date)`

	// Same exclusions as the renewals queue, for the same reasons: terminated
	// and churned are endings somebody already decided, and frozen is paused
	// on purpose rather than lapsing.
	expiringWhere = `m.gym_id = @gym
	                 AND m.deleted_at IS NULL
	                 AND m.expiry_date IS NOT NULL
	                 AND m.status NOT IN ('terminated', 'churned', 'frozen')
	                 AND m.expiry_date BETWEEN CAST(@from AS date) AND CAST(@to AS date)`
)

// ExpectedTotals sums the whole span in SQL.
//
// Deliberately not derived from the rows the list returns. The list is capped;
// the totals are not, and a headline that shifts when a cap is hit is worse
// than no headline.
func (r *Repository) ExpectedTotals(
	ctx context.Context, rng staffwork.Range,
) (expectedTotals, error) {
	tc := database.MustGetTenant(ctx)

	args := map[string]interface{}{
		"gym":  tc.GymID(),
		"from": rng.FromString(),
		"to":   rng.ToString(),
	}

	var out expectedTotals
	err := r.db.WithContext(ctx).Raw(`
		SELECT
		  (SELECT COUNT(*) FROM payments p WHERE `+raisedWhere+`)
		      AS raised_count,
		  COALESCE((SELECT SUM(p.amount_in_paise) FROM payments p
		             WHERE `+raisedWhere+`), 0)
		      AS raised_in_paise,
		  (SELECT COUNT(*) FROM members m WHERE `+expiringWhere+`)
		      AS expiring_count,
		  COALESCE((SELECT SUM(pl.price_in_paise)
		              FROM members m
		              LEFT JOIN membership_plans pl ON pl.id = m.membership_plan_id
		             WHERE `+expiringWhere+`), 0)
		      AS expiring_in_paise`, args).Scan(&out).Error
	return out, err
}

// ExpectedItems lists both kinds, soonest first.
//
// Fetches one more than the cap so the caller can tell a full page from a
// truncated one without a second count.
func (r *Repository) ExpectedItems(
	ctx context.Context, rng staffwork.Range,
) ([]expectedRow, error) {
	tc := database.MustGetTenant(ctx)

	args := map[string]interface{}{
		"gym":   tc.GymID(),
		"from":  rng.FromString(),
		"to":    rng.ToString(),
		"limit": ExpectedItemLimit + 1,
	}

	// UNION ALL rather than two round trips: the two kinds interleave by date,
	// and merging them in Go would mean paging each side blind.
	sql := `
		SELECT '` + KindRaised + `' AS kind,
		       m.id AS member_id,
		       ` + expectedMemberName + ` AS member,
		       COALESCE(m.phone, '') AS phone,
		       p.amount_in_paise,
		       p.due_date AS date,
		       p.id AS payment_id,
		       NULL::varchar AS plan_name,
		       NULL::timestamptz AS last_visit_at,
		       COALESCE(owed.amount, 0) AS owed_in_paise
		  FROM payments p
		  JOIN members m ON m.id = p.member_id AND m.deleted_at IS NULL
		  LEFT JOIN LATERAL (
		      SELECT SUM(o.amount_in_paise) AS amount
		        FROM payments o
		       WHERE o.gym_id = m.gym_id AND o.member_id = m.id
		         AND o.status IN ('pending', 'overdue')
		  ) owed ON true
		 WHERE ` + raisedWhere + `

		UNION ALL

		SELECT '` + KindExpiring + `' AS kind,
		       m.id AS member_id,
		       ` + expectedMemberName + ` AS member,
		       COALESCE(m.phone, '') AS phone,
		       COALESCE(pl.price_in_paise, 0) AS amount_in_paise,
		       m.expiry_date AS date,
		       NULL::bigint AS payment_id,
		       pl.name AS plan_name,
		       att.at AS last_visit_at,
		       COALESCE(owed.amount, 0) AS owed_in_paise
		  FROM members m
		  LEFT JOIN membership_plans pl ON pl.id = m.membership_plan_id
		  LEFT JOIN LATERAL (
		      SELECT MAX(a.checked_in_at) AS at
		        FROM attendance a
		       WHERE a.member_id = m.id
		  ) att ON true
		  LEFT JOIN LATERAL (
		      SELECT SUM(o.amount_in_paise) AS amount
		        FROM payments o
		       WHERE o.gym_id = m.gym_id AND o.member_id = m.id
		         AND o.status IN ('pending', 'overdue')
		  ) owed ON true
		 WHERE ` + expiringWhere + `

		 -- Soonest first. Raised before expiring on the same date, because one
		 -- is owed and the other is a hope.
		 ORDER BY date ASC, kind ASC, member ASC
		 LIMIT CAST(@limit AS int)`

	var rows []expectedRow
	err := r.db.WithContext(ctx).Raw(sql, args).Scan(&rows).Error
	return rows, err
}

// ExpectedBuckets returns the span's shape, grouped by day or by month.
//
// Grouped in SQL so an empty day is simply absent and the service can fill it
// in — a gap in a series has to be a zero, not a missing column, or the shape
// lies about which days are quiet.
func (r *Repository) ExpectedBuckets(
	ctx context.Context, rng staffwork.Range, byMonth bool,
) ([]ExpectedBucket, error) {
	tc := database.MustGetTenant(ctx)

	trunc := "day"
	if byMonth {
		trunc = "month"
	}

	args := map[string]interface{}{
		"gym":  tc.GymID(),
		"from": rng.FromString(),
		"to":   rng.ToString(),
	}

	sql := `
		SELECT key, label,
		       SUM(raised_in_paise)   AS raised_in_paise,
		       SUM(expiring_in_paise) AS expiring_in_paise,
		       SUM(raised_count)      AS raised_count,
		       SUM(expiring_count)    AS expiring_count
		  FROM (
		    SELECT TO_CHAR(DATE_TRUNC('` + trunc + `', p.due_date), 'YYYY-MM-DD') AS key,
		           TO_CHAR(DATE_TRUNC('` + trunc + `', p.due_date), 'YYYY-MM-DD') AS label,
		           SUM(p.amount_in_paise) AS raised_in_paise,
		           0::bigint              AS expiring_in_paise,
		           COUNT(*)               AS raised_count,
		           0                      AS expiring_count
		      FROM payments p
		     WHERE ` + raisedWhere + `
		     GROUP BY 1, 2

		    UNION ALL

		    SELECT TO_CHAR(DATE_TRUNC('` + trunc + `', m.expiry_date), 'YYYY-MM-DD') AS key,
		           TO_CHAR(DATE_TRUNC('` + trunc + `', m.expiry_date), 'YYYY-MM-DD') AS label,
		           0::bigint                       AS raised_in_paise,
		           COALESCE(SUM(pl.price_in_paise), 0) AS expiring_in_paise,
		           0                               AS raised_count,
		           COUNT(*)                        AS expiring_count
		      FROM members m
		      LEFT JOIN membership_plans pl ON pl.id = m.membership_plan_id
		     WHERE ` + expiringWhere + `
		     GROUP BY 1, 2
		  ) b
		 GROUP BY key, label
		 ORDER BY key ASC`

	var rows []ExpectedBucket
	err := r.db.WithContext(ctx).Raw(sql, args).Scan(&rows).Error
	return rows, err
}
