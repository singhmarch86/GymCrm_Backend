package activation

import (
	"context"
	"strings"
	"time"

	"gorm.io/gorm"

	"gymcrm/internal/database"
)

type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository { return &Repository{db: db} }

type memberRow struct {
	ID        int64
	Name      string
	JoinDate  time.Time
	Visits    int
	LastVisit *time.Time
	IsFrozen  bool
}

// LoadCohort returns every member inside their first 90 days, with their
// visit count and last visit.
//
// Filtered on join_date, never start_date: start_date moves forward on every
// renewal, so a two-year member who renewed last week would otherwise appear
// here as brand new (FR-10 §1).
func (r *Repository) LoadCohort(ctx context.Context, today time.Time) ([]Member, error) {
	tc := database.MustGetTenant(ctx)

	var rows []memberRow
	err := r.db.WithContext(ctx).Raw(`
		SELECT m.id,
		       TRIM(COALESCE(m.first_name,'') || ' ' || COALESCE(m.last_name,'')) AS name,
		       m.join_date,
		       COALESCE(a.visits, 0) AS visits,
		       a.last_visit,
		       (m.frozen_from IS NOT NULL
		        AND m.frozen_from <= CURRENT_DATE
		        AND (m.frozen_until IS NULL OR m.frozen_until >= CURRENT_DATE)) AS is_frozen
		FROM members m
		LEFT JOIN (
		    SELECT member_id, COUNT(*) AS visits, MAX(checked_in_date) AS last_visit
		    FROM attendance
		    WHERE gym_id = ?
		    GROUP BY member_id
		) a ON a.member_id = m.id
		WHERE m.gym_id = ?
		  AND m.deleted_at IS NULL
		  AND m.status = 'active'
		  AND m.join_date >= ?
		  AND m.join_date <= ?
		ORDER BY m.join_date DESC
	`, tc.GymID(), tc.GymID(),
		today.AddDate(0, 0, -programmeDays).Format("2006-01-02"),
		today.Format("2006-01-02")).Scan(&rows).Error
	if err != nil {
		return nil, err
	}

	out := make([]Member, 0, len(rows))
	for _, row := range rows {
		name := strings.TrimSpace(row.Name)
		if name == "" {
			name = "This member"
		}
		out = append(out, Member{
			ID: row.ID, Name: name, JoinDate: row.JoinDate,
			Visits: row.Visits, LastVisit: row.LastVisit, IsFrozen: row.IsFrozen,
		})
	}
	return out, nil
}

// NewAlert is one activation alert to raise.
type NewAlert struct {
	MemberID int64
	Type     State
	Severity string
	Message  string
}

// RaiseAlerts inserts into the shared alerts table. The partial unique index
// on (gym_id, member_id, alert_type) discards anything already open, so
// rescanning cannot duplicate a row.
func (r *Repository) RaiseAlerts(ctx context.Context, alerts []NewAlert) (int64, error) {
	if len(alerts) == 0 {
		return 0, nil
	}
	tc := database.MustGetTenant(ctx)
	gymID := tc.GymID()

	placeholders := make([]string, 0, len(alerts))
	args := make([]interface{}, 0, len(alerts)*5)
	for _, a := range alerts {
		placeholders = append(placeholders, "(?,?,?,?,?,false)")
		args = append(args, gymID, a.MemberID, string(a.Type), a.Severity, a.Message)
	}

	res := r.db.WithContext(ctx).Exec(`
		INSERT INTO retention_alerts
			(gym_id, member_id, alert_type, severity, message, is_resolved)
		VALUES `+strings.Join(placeholders, ",")+`
		ON CONFLICT (gym_id, member_id, alert_type) WHERE is_resolved = false
		DO NOTHING
	`, args...)
	return res.RowsAffected, res.Error
}

// StaleAlert names one activation alert that should be closed because it no
// longer describes the member.
type StaleAlert struct {
	MemberID int64
	Except   State // the one type to keep open, or "" to close all three
}

// ResolveStale closes activation alerts that no longer apply.
//
// This is what enforces "one member, one row" (FR-10 §3): when a member moves
// from slow start to going quiet, the old row is closed in the same scan that
// opens the new one, rather than both sitting in the queue.
func (r *Repository) ResolveStale(ctx context.Context, stale []StaleAlert) (int64, error) {
	if len(stale) == 0 {
		return 0, nil
	}
	tc := database.MustGetTenant(ctx)
	gymID := tc.GymID()

	var total int64
	// Grouped by "except" value so members needing the same treatment go in
	// one statement rather than one round trip each.
	byExcept := map[State][]int64{}
	for _, s := range stale {
		byExcept[s.Except] = append(byExcept[s.Except], s.MemberID)
	}

	for except, ids := range byExcept {
		res := r.db.WithContext(ctx).Exec(`
			UPDATE retention_alerts
			SET is_resolved = true, resolved_at = NOW()
			WHERE gym_id = ?
			  AND is_resolved = false
			  AND member_id IN (?)
			  AND alert_type IN ('activation_no_first_visit',
			                     'activation_slow_start',
			                     'activation_going_quiet')
			  AND alert_type <> ?
		`, gymID, ids, string(except))
		if res.Error != nil {
			return total, res.Error
		}
		total += res.RowsAffected
	}
	return total, nil
}

// ResolveGraduated closes any activation alert still open for a member who has
// passed 90 days or is no longer active. Without this a member who quietly
// aged out would keep an open alert forever, because the scan no longer looks
// at them at all.
func (r *Repository) ResolveGraduated(ctx context.Context, today time.Time) (int64, error) {
	tc := database.MustGetTenant(ctx)
	res := r.db.WithContext(ctx).Exec(`
		UPDATE retention_alerts a
		SET is_resolved = true, resolved_at = NOW()
		FROM members m
		WHERE m.id = a.member_id
		  AND a.gym_id = ?
		  AND a.is_resolved = false
		  AND a.alert_type IN ('activation_no_first_visit',
		                       'activation_slow_start',
		                       'activation_going_quiet')
		  AND (m.join_date < ? OR m.status <> 'active' OR m.deleted_at IS NOT NULL)
	`, tc.GymID(), today.AddDate(0, 0, -programmeDays).Format("2006-01-02"))
	return res.RowsAffected, res.Error
}

// ResolveSupersededInactivity closes generic inactivity alerts held by members
// who are inside the activation programme.
//
// Stopping the retention scan from *raising* these is not enough on its own:
// any alert opened before this rule existed — or before the member's 90-day
// window was recognised — would sit in the queue forever, which is exactly the
// duplicate listing FR-10 §4 forbids. This closes them.
func (r *Repository) ResolveSupersededInactivity(ctx context.Context, today time.Time) (int64, error) {
	tc := database.MustGetTenant(ctx)
	res := r.db.WithContext(ctx).Exec(`
		UPDATE retention_alerts a
		SET is_resolved = true, resolved_at = NOW()
		FROM members m
		WHERE m.id = a.member_id
		  AND a.gym_id = ?
		  AND a.is_resolved = false
		  AND a.alert_type IN ('inactive_1_week', 'inactive_2_weeks')
		  AND m.join_date >= ?
	`, tc.GymID(), today.AddDate(0, 0, -programmeDays).Format("2006-01-02"))
	return res.RowsAffected, res.Error
}

// AlertRow is an open activation alert with the numbers behind it.
type AlertRow struct {
	AlertID       int64      `json:"alert_id"`
	MemberID      int64      `json:"member_id"`
	MemberName    string     `json:"member_name"`
	Phone         *string    `json:"phone,omitempty"`
	AlertType     string     `json:"alert_type"`
	Severity      string     `json:"severity"`
	Message       string     `json:"message"`
	JoinDate      time.Time  `json:"join_date"`
	DaysSinceJoin int        `json:"days_since_join"`
	Visits        int        `json:"visits"`
	LastVisit     *time.Time `json:"last_visit,omitempty"`
	VisitsPerWeek float64    `json:"visits_per_week"`
}

// ListAlerts returns open activation alerts, most urgent first.
func (r *Repository) ListAlerts(ctx context.Context) ([]AlertRow, error) {
	tc := database.MustGetTenant(ctx)
	var rows []AlertRow
	err := r.db.WithContext(ctx).Raw(`
		SELECT a.id AS alert_id, a.member_id,
		       TRIM(COALESCE(m.first_name,'') || ' ' || COALESCE(m.last_name,'')) AS member_name,
		       m.phone, a.alert_type, a.severity, a.message,
		       m.join_date,
		       (CURRENT_DATE - m.join_date) AS days_since_join,
		       COALESCE(v.visits, 0) AS visits,
		       v.last_visit,
		       CASE WHEN CURRENT_DATE > m.join_date
		            THEN COALESCE(v.visits,0)::numeric / ((CURRENT_DATE - m.join_date)::numeric / 7)
		            ELSE 0 END AS visits_per_week
		FROM retention_alerts a
		JOIN members m ON m.id = a.member_id AND m.gym_id = a.gym_id
		LEFT JOIN (
		    SELECT member_id, COUNT(*) AS visits, MAX(checked_in_date) AS last_visit
		    FROM attendance WHERE gym_id = ? GROUP BY member_id
		) v ON v.member_id = m.id
		WHERE a.gym_id = ?
		  AND a.is_resolved = false
		  AND m.deleted_at IS NULL
		  AND a.alert_type IN ('activation_no_first_visit',
		                       'activation_slow_start',
		                       'activation_going_quiet')
		ORDER BY CASE a.alert_type
		           WHEN 'activation_no_first_visit' THEN 0
		           WHEN 'activation_going_quiet'    THEN 1
		           ELSE 2 END,
		         m.join_date DESC
	`, tc.GymID(), tc.GymID()).Scan(&rows).Error
	if err != nil {
		return nil, err
	}
	return rows, nil
}

// CohortRow is one join-month's activation funnel.
type CohortRow struct {
	JoinMonth      string `json:"join_month"`
	Joined         int    `json:"joined"`
	EverVisited    int    `json:"ever_visited"`
	FourInTwoWeeks int    `json:"four_in_two_weeks"`
	TwelveInMonth  int    `json:"twelve_in_first_month"`
	ActiveAtSixty  int    `json:"active_at_sixty_to_ninety"`

	// DataComplete is false when this cohort's first 90 days fall partly
	// outside the attendance history the gym actually has — either because
	// the gym is newer than that, or because they imported members without
	// importing check-ins. Those cohorts show near-zero on every step and
	// read as catastrophic onboarding when nothing is wrong at all, so the
	// screen must label them rather than let an owner draw the conclusion.
	DataComplete bool `json:"data_complete"`
}

// Funnel answers the owner's question rather than the front desk's: is
// onboarding working, and is it getting better or worse (FR-10 §5)?
//
// No target is applied to any step. A number GymCRM invented would be worse
// than no number — the comparison that matters is this gym against itself.
func (r *Repository) Funnel(ctx context.Context, months int) ([]CohortRow, error) {
	tc := database.MustGetTenant(ctx)
	var rows []CohortRow
	err := r.db.WithContext(ctx).Raw(`
		WITH cohort AS (
		    SELECT m.id, m.join_date,
		           to_char(m.join_date, 'YYYY-MM') AS join_month
		    FROM members m
		    WHERE m.gym_id = ?
		      AND m.deleted_at IS NULL
		      AND m.join_date >= (date_trunc('month', CURRENT_DATE) - make_interval(months => ?))
		), counted AS (
		    SELECT c.id, c.join_month,
		           COUNT(a.id) FILTER (WHERE a.id IS NOT NULL) AS total_visits,
		           COUNT(a.id) FILTER (WHERE a.checked_in_date < c.join_date + 14) AS v14,
		           COUNT(a.id) FILTER (WHERE a.checked_in_date < c.join_date + 30) AS v30,
		           COUNT(a.id) FILTER (WHERE a.checked_in_date >= c.join_date + 60
		                                 AND a.checked_in_date <  c.join_date + 90) AS v60_90
		    FROM cohort c
		    LEFT JOIN attendance a ON a.member_id = c.id AND a.gym_id = ?
		    GROUP BY c.id, c.join_month
		)
		SELECT c.join_month,
		       COUNT(*)                                        AS joined,
		       COUNT(*) FILTER (WHERE c.total_visits >= 1)     AS ever_visited,
		       COUNT(*) FILTER (WHERE c.v14 >= 4)              AS four_in_two_weeks,
		       COUNT(*) FILTER (WHERE c.v30 >= 12)             AS twelve_in_month,
		       COUNT(*) FILTER (WHERE c.v60_90 >= 1)           AS active_at_sixty,
		       -- Complete only if check-in history starts on or before the
		       -- first day of this cohort's month.
		       COALESCE(
		           (to_date(c.join_month || '-01', 'YYYY-MM-DD') >= h.first_checkin),
		           false) AS data_complete
		FROM counted c
		LEFT JOIN (
		    SELECT MIN(checked_in_date) AS first_checkin
		    FROM attendance WHERE gym_id = ?
		) h ON true
		GROUP BY c.join_month, h.first_checkin
		ORDER BY c.join_month DESC
	`, tc.GymID(), months, tc.GymID(), tc.GymID()).Scan(&rows).Error
	return rows, err
}
