package leads

import (
	"context"

	"gorm.io/gorm"

	"gymcrm/internal/database"
)

// ─── Activity writes ──────────────────────────────────────────────────────────

// LogActivity appends one timeline entry. Callers that are already inside a
// transaction should use logActivityTx so the entry commits atomically with
// whatever change it describes.
func (r *Repository) LogActivity(ctx context.Context, a *LeadActivity) error {
	tc := database.MustGetTenant(ctx)
	a.GymID = tc.GymID()
	if a.UserID == nil {
		uid := tc.UserID()
		a.UserID = &uid
	}
	return r.db.WithContext(ctx).Create(a).Error
}

// logActivityTx is the in-transaction variant. Used by status changes so an
// activity is never recorded for a transition that later rolls back.
func logActivityTx(tx *gorm.DB, gymID int64, a *LeadActivity) error {
	a.GymID = gymID
	return tx.Table("lead_activities").Create(map[string]interface{}{
		"gym_id":      a.GymID,
		"lead_id":     a.LeadID,
		"user_id":     a.UserID,
		"type":        string(a.Type),
		"note":        a.Note,
		"from_status": a.FromStatus,
		"to_status":   a.ToStatus,
	}).Error
}

// UpdateStatusWithActivity changes a lead's status and records the transition
// in one transaction, so the timeline can never disagree with the lead's
// actual state — either both land or neither does.
func (r *Repository) UpdateStatusWithActivity(
	ctx context.Context,
	leadID int64,
	from, to string,
	updates map[string]interface{},
	note *string,
) error {
	tc := database.MustGetTenant(ctx)
	gymID := tc.GymID()
	userID := tc.UserID()

	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Table("leads").
			Where("id = ? AND gym_id = ? AND deleted_at IS NULL", leadID, gymID).
			Updates(updates).Error; err != nil {
			return err
		}

		activityType := ActivityStageChange
		if to == string(LeadStatusLost) {
			activityType = ActivityLost
		}

		return logActivityTx(tx, gymID, &LeadActivity{
			LeadID:     leadID,
			UserID:     &userID,
			Type:       activityType,
			Note:       note,
			FromStatus: &from,
			ToStatus:   &to,
		})
	})
}

// ─── Activity reads ───────────────────────────────────────────────────────────

// ListActivities returns a lead's full timeline, newest first.
func (r *Repository) ListActivities(ctx context.Context, leadID int64) ([]LeadActivity, error) {
	tc := database.MustGetTenant(ctx)
	var out []LeadActivity
	err := r.db.WithContext(ctx).
		Table("lead_activities").
		Select(`lead_activities.*, COALESCE(users.name, '') AS user_name`).
		Joins("LEFT JOIN users ON users.id = lead_activities.user_id").
		Where("lead_activities.gym_id = ? AND lead_activities.lead_id = ?", tc.GymID(), leadID).
		Order("lead_activities.created_at DESC").
		Scan(&out).Error
	return out, err
}

// ─── Assignees ────────────────────────────────────────────────────────────────

// Assignee is a gym staff member who can own leads. Exposed under the leads
// API rather than a users module because lead assignment is currently the only
// consumer — this deliberately avoids standing up a whole users HTTP surface
// (and its auth/permission questions) for one dropdown.
type Assignee struct {
	ID        int64  `json:"id"`
	Name      string `json:"name"`
	Role      string `json:"role"`
	LeadCount int64  `json:"lead_count"` // open leads currently assigned
}

func (r *Repository) ListAssignees(ctx context.Context) ([]Assignee, error) {
	tc := database.MustGetTenant(ctx)
	var out []Assignee
	err := r.db.WithContext(ctx).Raw(`
		SELECT
			users.id,
			users.name,
			users.role,
			COUNT(leads.id) FILTER (
				WHERE leads.deleted_at IS NULL
				  AND leads.status NOT IN ('joined','lost')
			) AS lead_count
		FROM users
		LEFT JOIN leads ON leads.assigned_user_id = users.id
		WHERE users.gym_id = ? AND users.status = 'active'
		GROUP BY users.id, users.name, users.role
		ORDER BY users.name ASC
	`, tc.GymID()).Scan(&out).Error
	return out, err
}

// ─── Follow-up queue ──────────────────────────────────────────────────────────

// FollowUpBuckets splits actionable leads into what the staff should do now.
// Only open leads are included — a joined or lost lead needs no follow-up.
type FollowUpBuckets struct {
	Overdue  []Lead `json:"overdue"`
	Today    []Lead `json:"today"`
	Upcoming []Lead `json:"upcoming"`
	Trials   []Lead `json:"trials"` // trial_date today or later, still open
}

func (r *Repository) GetFollowUps(ctx context.Context) (*FollowUpBuckets, error) {
	tc := database.MustGetTenant(ctx)
	gymID := tc.GymID()
	out := &FollowUpBuckets{
		Overdue:  []Lead{},
		Today:    []Lead{},
		Upcoming: []Lead{},
		Trials:   []Lead{},
	}

	base := `
		SELECT leads.*, COALESCE(users.name, '') AS assigned_user_name
		FROM leads
		LEFT JOIN users ON users.id = leads.assigned_user_id
		WHERE leads.gym_id = ?
		  AND leads.deleted_at IS NULL
		  AND leads.status NOT IN ('joined','lost')
	`

	q := func(extra, order string, dest *[]Lead) error {
		return r.db.WithContext(ctx).Raw(base+extra+order, gymID).Scan(dest).Error
	}

	if err := q(` AND leads.follow_up_date < CURRENT_DATE`, ` ORDER BY leads.follow_up_date ASC`, &out.Overdue); err != nil {
		return nil, err
	}
	if err := q(` AND leads.follow_up_date = CURRENT_DATE`, ` ORDER BY leads.name ASC`, &out.Today); err != nil {
		return nil, err
	}
	if err := q(` AND leads.follow_up_date > CURRENT_DATE`, ` ORDER BY leads.follow_up_date ASC LIMIT 50`, &out.Upcoming); err != nil {
		return nil, err
	}
	if err := q(` AND leads.trial_date >= CURRENT_DATE`, ` ORDER BY leads.trial_date ASC LIMIT 50`, &out.Trials); err != nil {
		return nil, err
	}

	return out, nil
}

// ─── Pipeline analytics ───────────────────────────────────────────────────────

type FunnelStage struct {
	Status string `json:"status"`
	Count  int64  `json:"count"`
}

type SourcePerformance struct {
	Source   string  `json:"source"`
	Total    int64   `json:"total"`
	Joined   int64   `json:"joined"`
	Lost     int64   `json:"lost"`
	ConvRate float64 `json:"conversion_rate"` // joined / total, 0..100
}

type LostReasonCount struct {
	Reason string `json:"reason"`
	Count  int64  `json:"count"`
}

type StageDuration struct {
	Status  string  `json:"status"`
	AvgDays float64 `json:"avg_days"`
}

type AnalyticsData struct {
	Funnel        []FunnelStage       `json:"funnel"`
	BySource      []SourcePerformance `json:"by_source"`
	LostReasons   []LostReasonCount   `json:"lost_reasons"`
	StageDuration []StageDuration     `json:"stage_duration"`
}

func (r *Repository) GetAnalytics(ctx context.Context) (*AnalyticsData, error) {
	tc := database.MustGetTenant(ctx)
	gymID := tc.GymID()
	out := &AnalyticsData{
		Funnel:        []FunnelStage{},
		BySource:      []SourcePerformance{},
		LostReasons:   []LostReasonCount{},
		StageDuration: []StageDuration{},
	}

	// Funnel — counts per stage. Returned in PipelineOrder by the service so
	// the client never has to know the ordering.
	var funnel []FunnelStage
	if err := r.db.WithContext(ctx).Raw(`
		SELECT status, COUNT(*) AS count
		FROM leads
		WHERE gym_id = ? AND deleted_at IS NULL
		GROUP BY status
	`, gymID).Scan(&funnel).Error; err != nil {
		return nil, err
	}
	out.Funnel = funnel

	// Conversion by source — which channels actually produce members.
	if err := r.db.WithContext(ctx).Raw(`
		SELECT
			source,
			COUNT(*)                                              AS total,
			COUNT(*) FILTER (WHERE status = 'joined')             AS joined,
			COUNT(*) FILTER (WHERE status = 'lost')               AS lost,
			ROUND(
				100.0 * COUNT(*) FILTER (WHERE status = 'joined')
				/ NULLIF(COUNT(*), 0)
			, 1)                                                  AS conv_rate
		FROM leads
		WHERE gym_id = ? AND deleted_at IS NULL
		GROUP BY source
		ORDER BY total DESC
	`, gymID).Scan(&out.BySource).Error; err != nil {
		return nil, err
	}

	// Why leads are lost. Grouped on the free-text reason, trimmed/lowercased
	// so trivial casing differences collapse together.
	if err := r.db.WithContext(ctx).Raw(`
		SELECT
			COALESCE(NULLIF(TRIM(LOWER(lost_reason)), ''), 'not specified') AS reason,
			COUNT(*) AS count
		FROM leads
		WHERE gym_id = ? AND deleted_at IS NULL AND status = 'lost'
		GROUP BY reason
		ORDER BY count DESC
		LIMIT 10
	`, gymID).Scan(&out.LostReasons).Error; err != nil {
		return nil, err
	}

	// Average time spent in each stage, reconstructed from consecutive
	// stage_change rows. LEAD() gives each transition's successor, so the gap
	// between them is how long the lead sat in from_status. Transitions with
	// no successor (the lead's current stage) are excluded — that duration is
	// still accruing and would skew the average downward.
	if err := r.db.WithContext(ctx).Raw(`
		WITH transitions AS (
			SELECT
				lead_id,
				to_status,
				created_at,
				LEAD(created_at) OVER (PARTITION BY lead_id ORDER BY created_at) AS next_at
			FROM lead_activities
			WHERE gym_id = ? AND type = 'stage_change'
		)
		SELECT
			to_status AS status,
			ROUND(AVG(EXTRACT(EPOCH FROM (next_at - created_at)) / 86400.0)::numeric, 1) AS avg_days
		FROM transitions
		WHERE next_at IS NOT NULL
		GROUP BY to_status
	`, gymID).Scan(&out.StageDuration).Error; err != nil {
		return nil, err
	}

	return out, nil
}
