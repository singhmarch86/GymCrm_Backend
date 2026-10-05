package staffwork

import (
	"context"

	"gymcrm/internal/database"
)

// All three queries below run over the same eventSources union the day view
// uses, so a number on the analytics screen and the same number on the day
// screen come from one definition of "work". Two unions would drift, and the
// first person to notice would be an owner asking why the totals disagree.

type trendRow struct {
	Key           string
	Count         int
	AmountInPaise int64
}

// Trend groups recorded work by gym-local day or week.
//
// Grouped in IST before the date is taken, exactly like the day view: an 11pm
// sale belongs to the day the gym would call it, and comparing raw UTC puts
// every evening transaction on tomorrow.
func (r *Repository) Trend(
	ctx context.Context, rng Range, byWeek bool,
) ([]trendRow, error) {
	tc := database.MustGetTenant(ctx)

	unit := "day"
	if byWeek {
		unit = "week"
	}

	sql := `
		WITH events AS (` + eventSources + `)
		SELECT TO_CHAR(
		           DATE_TRUNC('` + unit + `',
		               (e.at AT TIME ZONE 'Asia/Kolkata')::date),
		           'YYYY-MM-DD') AS key,
		       COUNT(*) AS count,
		       COALESCE(SUM(e.amount), 0) AS amount_in_paise
		  FROM events e
		 WHERE e.at IS NOT NULL
		   AND (e.at AT TIME ZONE 'Asia/Kolkata')::date
		       BETWEEN CAST(@from AS date) AND CAST(@to AS date)
		 GROUP BY 1
		 ORDER BY 1`

	var rows []trendRow
	err := r.db.WithContext(ctx).Raw(sql, map[string]interface{}{
		"gym":  tc.GymID(),
		"from": rng.FromString(),
		"to":   rng.ToString(),
	}).Scan(&rows).Error
	return rows, err
}

type categoryRow struct {
	Category      string
	Count         int
	AmountInPaise int64
}

func (r *Repository) CategoryTotals(
	ctx context.Context, rng Range,
) ([]categoryRow, error) {
	tc := database.MustGetTenant(ctx)

	sql := `
		WITH events AS (` + eventSources + `)
		SELECT e.category,
		       COUNT(*) AS count,
		       COALESCE(SUM(e.amount), 0) AS amount_in_paise
		  FROM events e
		 WHERE e.at IS NOT NULL
		   AND (e.at AT TIME ZONE 'Asia/Kolkata')::date
		       BETWEEN CAST(@from AS date) AND CAST(@to AS date)
		 GROUP BY e.category
		 ORDER BY count DESC`

	var rows []categoryRow
	err := r.db.WithContext(ctx).Raw(sql, map[string]interface{}{
		"gym":  tc.GymID(),
		"from": rng.FromString(),
		"to":   rng.ToString(),
	}).Scan(&rows).Error
	return rows, err
}

type personRow struct {
	UserID        *int64
	Name          string
	Role          string
	Count         int
	AmountInPaise int64
	PreviousCount int
}

// PersonTotals returns each person's work for the span alongside the same
// person's work in the equivalent span immediately before it.
//
// The previous period is the only comparison this screen offers. One query
// covering both windows rather than two round trips, because the two must use
// identical filters — a subtle difference between them would show up as a
// change that never happened.
//
// Ordered by name in SQL, so a client cannot accidentally receive something
// that looks like a ranking and render it as one.
func (r *Repository) PersonTotals(
	ctx context.Context, rng Range, prevFrom, prevTo string,
) ([]personRow, error) {
	tc := database.MustGetTenant(ctx)

	sql := `
		WITH events AS (` + eventSources + `),
		dated AS (
		    SELECT e.user_id, e.amount,
		           (e.at AT TIME ZONE 'Asia/Kolkata')::date AS d
		      FROM events e
		     WHERE e.at IS NOT NULL
		)
		SELECT d.user_id,
		       COALESCE(u.name, 'Unattributed') AS name,
		       COALESCE(u.role, '') AS role,
		       COUNT(*) FILTER (
		           WHERE d.d BETWEEN CAST(@from AS date) AND CAST(@to AS date)
		       ) AS count,
		       COALESCE(SUM(d.amount) FILTER (
		           WHERE d.d BETWEEN CAST(@from AS date) AND CAST(@to AS date)
		       ), 0) AS amount_in_paise,
		       COUNT(*) FILTER (
		           WHERE d.d BETWEEN CAST(@pfrom AS date) AND CAST(@pto AS date)
		       ) AS previous_count
		  FROM dated d
		  LEFT JOIN users u ON u.id = d.user_id
		 WHERE d.d BETWEEN CAST(@pfrom AS date) AND CAST(@to AS date)
		 GROUP BY d.user_id, u.name, u.role
		 -- By name, never by output. A list sorted by count is a ranking
		 -- whatever the heading above it says (FR-13 §1).
		 HAVING COUNT(*) FILTER (
		     WHERE d.d BETWEEN CAST(@from AS date) AND CAST(@to AS date)
		 ) > 0
		 ORDER BY name ASC`

	var rows []personRow
	err := r.db.WithContext(ctx).Raw(sql, map[string]interface{}{
		"gym":   tc.GymID(),
		"from":  rng.FromString(),
		"to":    rng.ToString(),
		"pfrom": prevFrom,
		"pto":   prevTo,
	}).Scan(&rows).Error
	return rows, err
}
