package rhythm

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

// MemberCheckIns is one member's raw timestamps, ready for Analyse.
type MemberCheckIns struct {
	MemberID int64
	Name     string
	CheckIns []time.Time
}

type checkInRow struct {
	MemberID    int64
	Name        string
	CheckedInAt time.Time
}

// LoadCheckIns pulls every check-in in the analysis span for members whose
// membership is still active — there is no point telling staff that someone who
// already left has stopped keeping their slot.
func (r *Repository) LoadCheckIns(ctx context.Context, asOf time.Time) ([]MemberCheckIns, error) {
	tc := database.MustGetTenant(ctx)

	from := asOf.AddDate(0, 0, -baselineDays)
	var rows []checkInRow
	err := r.db.WithContext(ctx).Raw(`
		SELECT a.member_id,
		       TRIM(COALESCE(m.first_name,'') || ' ' || COALESCE(m.last_name,'')) AS name,
		       a.checked_in_at
		FROM attendance a
		JOIN members m ON m.id = a.member_id AND m.gym_id = a.gym_id
		WHERE a.gym_id = ?
		  AND m.deleted_at IS NULL
		  AND m.status = 'active'
		  AND a.checked_in_date >= ?
		  AND a.checked_in_date <= ?
		ORDER BY a.member_id, a.checked_in_at
	`, tc.GymID(), from.Format("2006-01-02"), asOf.Format("2006-01-02")).Scan(&rows).Error
	if err != nil {
		return nil, err
	}

	// Rows arrive ordered by member, so grouping is a single pass.
	var out []MemberCheckIns
	for _, row := range rows {
		if n := len(out); n > 0 && out[n-1].MemberID == row.MemberID {
			out[n-1].CheckIns = append(out[n-1].CheckIns, row.CheckedInAt)
			continue
		}
		name := strings.TrimSpace(row.Name)
		if name == "" {
			name = "This member"
		}
		out = append(out, MemberCheckIns{MemberID: row.MemberID, Name: name, CheckIns: []time.Time{row.CheckedInAt}})
	}
	return out, nil
}

// UpsertProfiles rewrites the stored rhythm description for every member the
// scan evaluated. Written for eligible members whether or not they broke
// rhythm — a profile is a description, not an accusation (FR-09 §4).
func (r *Repository) UpsertProfiles(ctx context.Context, asOf time.Time, profiles []*Profile) error {
	if len(profiles) == 0 {
		return nil
	}
	tc := database.MustGetTenant(ctx)
	gymID := tc.GymID()
	date := asOf.Format("2006-01-02")

	placeholders := make([]string, 0, len(profiles))
	args := make([]interface{}, 0, len(profiles)*16)
	for _, p := range profiles {
		placeholders = append(placeholders, "(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,NOW())")
		args = append(args,
			gymID, p.MemberID, date, p.AnchorMinute,
			p.BaselineVisits, p.BaselineWeeks, p.BaselineConsistency, p.BaselineRate,
			p.RecentVisits, p.RecentConsistency, p.RecentRate,
			p.BaselineOnSlot, p.RecentOnSlot,
			p.BaselineWeekdays, p.RecentWeekdays, p.IsBroken,
		)
	}

	return r.db.WithContext(ctx).Exec(`
		INSERT INTO member_rhythm_profiles
			(gym_id, member_id, computed_as_of, anchor_minute,
			 baseline_visits, baseline_weeks, baseline_consistency, baseline_rate,
			 recent_visits, recent_consistency, recent_rate,
			 baseline_on_slot, recent_on_slot,
			 baseline_weekdays, recent_weekdays, is_broken, updated_at)
		VALUES `+strings.Join(placeholders, ",")+`
		ON CONFLICT (gym_id, member_id) DO UPDATE SET
			computed_as_of = EXCLUDED.computed_as_of,
			anchor_minute = EXCLUDED.anchor_minute,
			baseline_visits = EXCLUDED.baseline_visits,
			baseline_weeks = EXCLUDED.baseline_weeks,
			baseline_consistency = EXCLUDED.baseline_consistency,
			baseline_rate = EXCLUDED.baseline_rate,
			recent_visits = EXCLUDED.recent_visits,
			recent_consistency = EXCLUDED.recent_consistency,
			recent_rate = EXCLUDED.recent_rate,
			baseline_on_slot = EXCLUDED.baseline_on_slot,
			recent_on_slot = EXCLUDED.recent_on_slot,
			baseline_weekdays = EXCLUDED.baseline_weekdays,
			recent_weekdays = EXCLUDED.recent_weekdays,
			is_broken = EXCLUDED.is_broken,
			updated_at = NOW()
	`, args...).Error
}

// NewAlert is one rhythm-break alert to raise.
type NewAlert struct {
	MemberID int64
	Severity string
	Message  string
}

// RaiseAlerts inserts into the existing retention_alerts table. Dedup is the
// database's job: the partial unique index on (gym_id, member_id, alert_type)
// WHERE NOT resolved discards anything already open, so rescanning — or two
// scans racing — cannot double-list a member.
func (r *Repository) RaiseAlerts(ctx context.Context, alerts []NewAlert) (int64, error) {
	if len(alerts) == 0 {
		return 0, nil
	}
	tc := database.MustGetTenant(ctx)
	gymID := tc.GymID()

	placeholders := make([]string, 0, len(alerts))
	args := make([]interface{}, 0, len(alerts)*4)
	for _, a := range alerts {
		placeholders = append(placeholders, "(?,?,'rhythm_break',?,?,false)")
		args = append(args, gymID, a.MemberID, a.Severity, a.Message)
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

// ResolveRecovered closes open rhythm-break alerts for members who are keeping
// their slot again. Note there is deliberately no rule closing an alert because
// the member went inactive: if someone breaks rhythm and then stops coming,
// that is the feature being right, and a human should close it (FR-09 §5).
func (r *Repository) ResolveRecovered(ctx context.Context, memberIDs []int64) (int64, error) {
	if len(memberIDs) == 0 {
		return 0, nil
	}
	tc := database.MustGetTenant(ctx)
	res := r.db.WithContext(ctx).Exec(`
		UPDATE retention_alerts
		SET is_resolved = true, resolved_at = NOW()
		WHERE gym_id = ?
		  AND alert_type = 'rhythm_break'
		  AND is_resolved = false
		  AND member_id IN (?)
	`, tc.GymID(), memberIDs)
	return res.RowsAffected, res.Error
}

// BreakRow is an open rhythm-break alert with the numbers behind it.
type BreakRow struct {
	AlertID    int64     `json:"alert_id"`
	MemberID   int64     `json:"member_id"`
	MemberName string    `json:"member_name"`
	Phone      *string   `json:"phone,omitempty"`
	Severity   string    `json:"severity"`
	Message    string    `json:"message"`
	CreatedAt  time.Time `json:"created_at"`

	AnchorMinute        int     `json:"anchor_minute"`
	UsualTime           string  `json:"usual_time"`
	BaselineVisits      int     `json:"baseline_visits"`
	BaselineOnSlot      int     `json:"baseline_on_slot"`
	BaselineConsistency float64 `json:"baseline_consistency"`
	BaselineRate        float64 `json:"baseline_rate"`
	RecentVisits        int     `json:"recent_visits"`
	RecentOnSlot        int     `json:"recent_on_slot"`
	RecentConsistency   float64 `json:"recent_consistency"`
	RecentRate          float64 `json:"recent_rate"`
	BaselineWeekdays    string  `json:"baseline_weekdays"`
	RecentWeekdays      string  `json:"recent_weekdays"`
}

// ListBreaks returns open rhythm-break alerts, most severe first.
func (r *Repository) ListBreaks(ctx context.Context) ([]BreakRow, error) {
	tc := database.MustGetTenant(ctx)
	var rows []BreakRow
	err := r.db.WithContext(ctx).Raw(`
		SELECT a.id AS alert_id, a.member_id,
		       TRIM(COALESCE(m.first_name,'') || ' ' || COALESCE(m.last_name,'')) AS member_name,
		       m.phone, a.severity, a.message, a.created_at,
		       COALESCE(p.anchor_minute, 0) AS anchor_minute,
		       COALESCE(p.baseline_visits, 0) AS baseline_visits,
		       COALESCE(p.baseline_on_slot, 0) AS baseline_on_slot,
		       COALESCE(p.baseline_consistency, 0) AS baseline_consistency,
		       COALESCE(p.baseline_rate, 0) AS baseline_rate,
		       COALESCE(p.recent_visits, 0) AS recent_visits,
		       COALESCE(p.recent_on_slot, 0) AS recent_on_slot,
		       COALESCE(p.recent_consistency, 0) AS recent_consistency,
		       COALESCE(p.recent_rate, 0) AS recent_rate,
		       COALESCE(p.baseline_weekdays, '.......') AS baseline_weekdays,
		       COALESCE(p.recent_weekdays, '.......') AS recent_weekdays
		FROM retention_alerts a
		JOIN members m ON m.id = a.member_id AND m.gym_id = a.gym_id
		LEFT JOIN member_rhythm_profiles p
		       ON p.member_id = a.member_id AND p.gym_id = a.gym_id
		WHERE a.gym_id = ?
		  AND a.alert_type = 'rhythm_break'
		  AND a.is_resolved = false
		  AND m.deleted_at IS NULL
		ORDER BY CASE a.severity WHEN 'high' THEN 0 WHEN 'medium' THEN 1 ELSE 2 END,
		         a.created_at DESC
	`, tc.GymID()).Scan(&rows).Error
	if err != nil {
		return nil, err
	}
	for i := range rows {
		rows[i].UsualTime = formatMinute(rows[i].AnchorMinute)
	}
	return rows, nil
}

// ProfileRow is one member's stored rhythm description.
type ProfileRow struct {
	MemberID            int64     `json:"member_id"`
	ComputedAsOf        time.Time `json:"computed_as_of"`
	AnchorMinute        int       `json:"anchor_minute"`
	UsualTime           string    `json:"usual_time"`
	BaselineVisits      int       `json:"baseline_visits"`
	BaselineWeeks       int       `json:"baseline_weeks"`
	BaselineOnSlot      int       `json:"baseline_on_slot"`
	BaselineConsistency float64   `json:"baseline_consistency"`
	BaselineRate        float64   `json:"baseline_rate"`
	RecentVisits        int       `json:"recent_visits"`
	RecentOnSlot        int       `json:"recent_on_slot"`
	RecentConsistency   float64   `json:"recent_consistency"`
	RecentRate          float64   `json:"recent_rate"`
	BaselineWeekdays    string    `json:"baseline_weekdays"`
	RecentWeekdays      string    `json:"recent_weekdays"`
	IsBroken            bool      `json:"is_broken"`
}

// GetProfile returns one member's profile, or nil if the last scan never had
// enough data to describe them.
func (r *Repository) GetProfile(ctx context.Context, memberID int64) (*ProfileRow, error) {
	tc := database.MustGetTenant(ctx)
	var rows []ProfileRow
	err := r.db.WithContext(ctx).Raw(`
		SELECT member_id, computed_as_of, anchor_minute,
		       baseline_visits, baseline_weeks, baseline_on_slot,
		       baseline_consistency, baseline_rate,
		       recent_visits, recent_on_slot, recent_consistency, recent_rate,
		       baseline_weekdays, recent_weekdays, is_broken
		FROM member_rhythm_profiles
		WHERE gym_id = ? AND member_id = ?
	`, tc.GymID(), memberID).Scan(&rows).Error
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, nil
	}
	rows[0].UsualTime = formatMinute(rows[0].AnchorMinute)
	return &rows[0], nil
}
