package retention

import (
	"context"
	"fmt"
	"strings"

	"gorm.io/gorm"

	"gymcrm/internal/database"
)

type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository {
	return &Repository{db: db}
}

// Candidate is a member matched by one of the retention policies, carrying just
// enough context to render a message.
type Candidate struct {
	MemberID   int64  `json:"member_id"`
	MemberName string `json:"member_name"`
	Phone      string `json:"phone"`
	DaysValue  int    `json:"days_value"` // days until expiry, or days since last check-in
}

// AlertRow is an alert joined to its member, which is all the UI ever needs.
type AlertRow struct {
	ID         int64   `json:"id"`
	MemberID   int64   `json:"member_id"`
	MemberName string  `json:"member_name"`
	Phone      string  `json:"phone"`
	AlertType  string  `json:"alert_type"`
	Severity   string  `json:"severity"`
	Message    string  `json:"message"`
	IsResolved bool    `json:"is_resolved"`
	CreatedAt  string  `json:"created_at"`
	ResolvedAt *string `json:"resolved_at,omitempty"`

	// Accountability: who handled it and what they did.
	ResolvedBy     *int64  `json:"resolved_by,omitempty"`
	ResolvedByName *string `json:"resolved_by_name,omitempty"` // resolved via JOIN
	ActionNote     *string `json:"action_note,omitempty"`
}

// ─── Policy candidate queries ─────────────────────────────────────────────────

// FindExpiringInDays returns active members whose membership lapses in exactly
// [days] days. "Exactly" matters: a member 3 days out would otherwise also match
// a 2-day and 1-day rule on later scans and collect several near-identical
// alerts, which the dedup index cannot catch because the types differ.
func (r *Repository) FindExpiringInDays(ctx context.Context, days int) ([]Candidate, error) {
	tc := database.MustGetTenant(ctx)
	var out []Candidate
	err := r.db.WithContext(ctx).Raw(`
		SELECT
			id AS member_id,
			TRIM(first_name || ' ' || COALESCE(last_name, '')) AS member_name,
			phone,
			(expiry_date - CURRENT_DATE) AS days_value
		FROM members
		WHERE gym_id = ?
		  AND deleted_at IS NULL
		  AND status = 'active'
		  AND expiry_date IS NOT NULL
		  AND expiry_date - CURRENT_DATE = ?
	`, tc.GymID(), days).Scan(&out).Error
	return out, err
}

// FindExpiredWithoutRenewal returns members already past expiry. The window is
// capped at 90 days so a long-dormant database does not raise alerts for people
// who left a year ago and were never going to come back.
func (r *Repository) FindExpiredWithoutRenewal(ctx context.Context) ([]Candidate, error) {
	tc := database.MustGetTenant(ctx)
	var out []Candidate
	err := r.db.WithContext(ctx).Raw(`
		SELECT
			id AS member_id,
			TRIM(first_name || ' ' || COALESCE(last_name, '')) AS member_name,
			phone,
			(CURRENT_DATE - expiry_date) AS days_value
		FROM members
		WHERE gym_id = ?
		  AND deleted_at IS NULL
		  AND expiry_date IS NOT NULL
		  AND expiry_date < CURRENT_DATE
		  AND CURRENT_DATE - expiry_date BETWEEN 1 AND 90
	`, tc.GymID()).Scan(&out).Error
	return out, err
}

// FindInactive returns members whose membership is still active but who have not
// checked in for at least [days] days — the paying-but-drifting cohort that
// churns at renewal. Members with no attendance at all are included, dated from
// when they joined.
//
// The upper bound keeps the tiers mutually exclusive: without it, someone absent
// 20 days matches both the 1-week and 2-week rule and gets two alerts saying
// the same thing.
func (r *Repository) FindInactive(ctx context.Context, minDays, maxDays int) ([]Candidate, error) {
	tc := database.MustGetTenant(ctx)

	upper := "AND days_since >= ?"
	args := []interface{}{tc.GymID(), minDays}
	if maxDays > 0 {
		upper = "AND days_since >= ? AND days_since < ?"
		args = []interface{}{tc.GymID(), minDays, maxDays}
	}

	query := fmt.Sprintf(`
		WITH last_seen AS (
			SELECT
				m.id,
				TRIM(m.first_name || ' ' || COALESCE(m.last_name, '')) AS member_name,
				m.phone,
				CURRENT_DATE - COALESCE(MAX(a.checked_in_date), m.created_at::date) AS days_since
			FROM members m
			LEFT JOIN attendance a
			       ON a.member_id = m.id AND a.gym_id = m.gym_id
			WHERE m.gym_id = ?
			  AND m.deleted_at IS NULL
			  AND m.status = 'active'
			GROUP BY m.id, m.first_name, m.last_name, m.phone, m.created_at
		)
		SELECT id AS member_id, member_name, phone, days_since AS days_value
		FROM last_seen
		WHERE TRUE %s
	`, upper)

	var out []Candidate
	err := r.db.WithContext(ctx).Raw(query, args...).Scan(&out).Error
	return out, err
}

// ─── Alert writes ─────────────────────────────────────────────────────────────

// NewAlert is one row to insert.
type NewAlert struct {
	MemberID  int64
	AlertType AlertType
	Severity  Severity
	Message   string
}

// InsertAlerts bulk-inserts, relying on the partial unique index
// idx_alerts_no_duplicate (gym_id, member_id, alert_type) WHERE is_resolved = false
// to discard anything already open. Dedup therefore happens in the database
// rather than in application logic, so a rescan — or two scans racing — cannot
// produce duplicates. Returns how many rows were actually new.
func (r *Repository) InsertAlerts(ctx context.Context, alerts []NewAlert) (int64, error) {
	if len(alerts) == 0 {
		return 0, nil
	}
	tc := database.MustGetTenant(ctx)
	gymID := tc.GymID()

	placeholders := make([]string, 0, len(alerts))
	args := make([]interface{}, 0, len(alerts)*5)
	for _, a := range alerts {
		placeholders = append(placeholders, "(?, ?, ?, ?, ?, false)")
		args = append(args, gymID, a.MemberID, string(a.AlertType), string(a.Severity), a.Message)
	}

	sql := `
		INSERT INTO retention_alerts
			(gym_id, member_id, alert_type, severity, message, is_resolved)
		VALUES ` + strings.Join(placeholders, ", ") + `
		ON CONFLICT (gym_id, member_id, alert_type) WHERE is_resolved = false
		DO NOTHING
	`

	res := r.db.WithContext(ctx).Exec(sql, args...)
	return res.RowsAffected, res.Error
}

// ─── Auto-resolution ──────────────────────────────────────────────────────────

// AutoResolve closes alerts whose underlying problem has gone away, so staff
// never tick off something the system can already see was handled.
//
// Returns the number of alerts closed.
func (r *Repository) AutoResolve(ctx context.Context) (int64, error) {
	tc := database.MustGetTenant(ctx)
	gymID := tc.GymID()
	var total int64

	// Expiry alerts resolve when the expiry date has moved *beyond the window
	// the alert was about* — that is what a renewal looks like.
	//
	// The threshold has to be per-type. "Expiry is in the future" is NOT a
	// renewal signal for an expiring_in_3_days alert, because that alert is
	// raised precisely while expiry is still 3 days out: such a rule closes the
	// alert the scan just created, and the next scan raises it again, forever.
	// Each type therefore resolves only once expiry passes its own horizon.
	res := r.db.WithContext(ctx).Exec(`
		UPDATE retention_alerts a
		SET is_resolved = true, resolved_at = NOW()
		FROM members m
		WHERE a.member_id = m.id
		  AND a.gym_id = ?
		  AND a.is_resolved = false
		  AND m.expiry_date IS NOT NULL
		  AND (
		        -- renewed well past the 3-day warning window
		        (a.alert_type = 'expiring_in_3_days'
		           AND m.expiry_date - CURRENT_DATE > ?)
		        -- renewed at all: no longer expiring today
		     OR (a.alert_type = 'expiring_today'
		           AND m.expiry_date > CURRENT_DATE)
		        -- renewed at all: no longer lapsed
		     OR (a.alert_type = 'expired_no_renewal'
		           AND m.expiry_date >= CURRENT_DATE)
		      )
	`, gymID, expiringSoonDays)
	if res.Error != nil {
		return total, res.Error
	}
	total += res.RowsAffected

	// Inactivity alerts: the member has checked in since the alert was raised.
	res = r.db.WithContext(ctx).Exec(`
		UPDATE retention_alerts a
		SET is_resolved = true, resolved_at = NOW()
		WHERE a.gym_id = ?
		  AND a.is_resolved = false
		  AND a.alert_type IN ('inactive_1_week','inactive_2_weeks')
		  AND EXISTS (
			  SELECT 1 FROM attendance att
			  WHERE att.member_id = a.member_id
			    AND att.gym_id = a.gym_id
			    AND att.checked_in_date >= a.created_at::date
		  )
	`, gymID)
	if res.Error != nil {
		return total, res.Error
	}
	total += res.RowsAffected

	// Any alert for a member who has since been deleted is moot.
	res = r.db.WithContext(ctx).Exec(`
		UPDATE retention_alerts a
		SET is_resolved = true, resolved_at = NOW()
		FROM members m
		WHERE a.member_id = m.id
		  AND a.gym_id = ?
		  AND a.is_resolved = false
		  AND m.deleted_at IS NOT NULL
	`, gymID)
	if res.Error != nil {
		return total, res.Error
	}
	total += res.RowsAffected

	return total, nil
}

// ─── Alert reads ──────────────────────────────────────────────────────────────

func (r *Repository) ListAlerts(ctx context.Context, severity string, includeResolved bool) ([]AlertRow, error) {
	tc := database.MustGetTenant(ctx)

	conditions := []string{"a.gym_id = ?"}
	args := []interface{}{tc.GymID()}

	if !includeResolved {
		conditions = append(conditions, "a.is_resolved = false")
	}
	if severity != "" {
		conditions = append(conditions, "a.severity = ?")
		args = append(args, severity)
	}

	query := `
		SELECT
			a.id, a.member_id,
			TRIM(m.first_name || ' ' || COALESCE(m.last_name, '')) AS member_name,
			m.phone,
			a.alert_type, a.severity, a.message, a.is_resolved,
			a.created_at, a.resolved_at,
			a.resolved_by, u.name AS resolved_by_name, a.action_note
		FROM retention_alerts a
		JOIN members m ON m.id = a.member_id
		LEFT JOIN users u ON u.id = a.resolved_by
		WHERE ` + strings.Join(conditions, " AND ") + `
		ORDER BY
			CASE a.severity WHEN 'high' THEN 0 WHEN 'medium' THEN 1 ELSE 2 END,
			a.created_at DESC
		LIMIT 300
	`

	var out []AlertRow
	err := r.db.WithContext(ctx).Raw(query, args...).Scan(&out).Error
	return out, err
}

// ResolveAlert closes an alert and records who did it. note may be nil when the
// staff member ticks it off without explaining — better to capture the actor
// alone than to force a note and have people type "." to get past it.
func (r *Repository) ResolveAlert(ctx context.Context, id int64, note *string) (int64, error) {
	tc := database.MustGetTenant(ctx)
	userID := tc.UserID()
	res := r.db.WithContext(ctx).Exec(`
		UPDATE retention_alerts
		SET is_resolved = true,
		    resolved_at = NOW(),
		    resolved_by = ?,
		    action_note = ?
		WHERE id = ? AND gym_id = ? AND is_resolved = false
	`, userID, note, id, tc.GymID())
	return res.RowsAffected, res.Error
}

// HandledItem is one alert a staff member closed — the evidence behind their
// count. A bare tally is unverifiable; naming the members makes the work
// checkable by whoever reads it.
type HandledItem struct {
	AlertID    int64   `json:"alert_id"`
	MemberID   int64   `json:"member_id"`
	MemberName string  `json:"member_name"`
	AlertType  string  `json:"alert_type"`
	ActionNote *string `json:"action_note,omitempty"`
	ResolvedAt string  `json:"resolved_at"`
}

// StaffActivity summarises who has been working the at-risk list, which is the
// question this whole migration exists to answer.
type StaffActivity struct {
	UserID        *int64        `json:"user_id,omitempty"`
	Name          *string       `json:"name,omitempty"`
	ResolvedCount int64         `json:"resolved_count"`
	Recent        []HandledItem `json:"recent"`
}

// resolvedRow is one flat row before grouping.
type resolvedRow struct {
	UserID     *int64
	Name       *string
	AlertID    int64
	MemberID   int64
	MemberName string
	AlertType  string
	ActionNote *string
	ResolvedAt string
}

// ResolvedByStaff returns per-staff counts plus the most recent items behind
// them. One query, grouped in Go: a per-user LATERAL would be tidier SQL but
// this window is small (a week of manual resolutions) and the flat scan keeps
// the query readable.
func (r *Repository) ResolvedByStaff(ctx context.Context, sinceDays, recentPerUser int) ([]StaffActivity, error) {
	tc := database.MustGetTenant(ctx)

	var rows []resolvedRow
	err := r.db.WithContext(ctx).Raw(`
		SELECT
			a.resolved_by AS user_id,
			u.name,
			a.id AS alert_id,
			a.member_id,
			TRIM(m.first_name || ' ' || COALESCE(m.last_name, '')) AS member_name,
			a.alert_type,
			a.action_note,
			a.resolved_at::text AS resolved_at
		FROM retention_alerts a
		JOIN members m ON m.id = a.member_id
		LEFT JOIN users u ON u.id = a.resolved_by
		WHERE a.gym_id = ?
		  AND a.is_resolved = true
		  AND a.resolved_at >= NOW() - MAKE_INTERVAL(days => ?)
		ORDER BY a.resolved_at DESC
	`, tc.GymID(), sinceDays).Scan(&rows).Error
	if err != nil {
		return nil, err
	}

	// Group by user, preserving the newest-first order the query established.
	// A nil UserID (auto-resolved, or closed before resolved_by existed) is its
	// own bucket rather than being folded into anyone's total.
	order := []string{}
	byKey := map[string]*StaffActivity{}

	for _, row := range rows {
		key := "system"
		if row.UserID != nil {
			key = fmt.Sprintf("u%d", *row.UserID)
		}
		entry, seen := byKey[key]
		if !seen {
			entry = &StaffActivity{
				UserID: row.UserID,
				Name:   row.Name,
				Recent: []HandledItem{},
			}
			byKey[key] = entry
			order = append(order, key)
		}
		entry.ResolvedCount++
		if len(entry.Recent) < recentPerUser {
			entry.Recent = append(entry.Recent, HandledItem{
				AlertID:    row.AlertID,
				MemberID:   row.MemberID,
				MemberName: row.MemberName,
				AlertType:  row.AlertType,
				ActionNote: row.ActionNote,
				ResolvedAt: row.ResolvedAt,
			})
		}
	}

	out := make([]StaffActivity, 0, len(order))
	for _, k := range order {
		out = append(out, *byKey[k])
	}
	return out, nil
}

// CountsBySeverity backs the dashboard badge and the screen's bucket headers.
func (r *Repository) CountsBySeverity(ctx context.Context) (map[string]int64, error) {
	tc := database.MustGetTenant(ctx)
	type row struct {
		Severity string
		Count    int64
	}
	var rows []row
	err := r.db.WithContext(ctx).Raw(`
		SELECT severity, COUNT(*) AS count
		FROM retention_alerts
		WHERE gym_id = ? AND is_resolved = false
		GROUP BY severity
	`, tc.GymID()).Scan(&rows).Error
	if err != nil {
		return nil, err
	}
	out := map[string]int64{"high": 0, "medium": 0, "low": 0}
	for _, r := range rows {
		out[r.Severity] = r.Count
	}
	return out, nil
}

// LastScanAt reports when the most recent alert was raised, which is the closest
// proxy for "when did the last scan run" without a separate bookkeeping table.
func (r *Repository) LastScanAt(ctx context.Context) (*string, error) {
	tc := database.MustGetTenant(ctx)
	var out *string
	err := r.db.WithContext(ctx).Raw(`
		SELECT MAX(created_at)::text FROM retention_alerts WHERE gym_id = ?
	`, tc.GymID()).Scan(&out).Error
	return out, err
}
