package leads

import (
	"context"
	"strconv"
	"time"

	"gymcrm/internal/database"
)

// WorkflowRow is one lead as the workflow sees it: who owns it, what is next,
// and how long it has been sitting where it is.
type WorkflowRow struct {
	Lead
	AssignedUserName *string `gorm:"->"`

	// Days in the current stage, from the most recent stage_change in
	// lead_activities — falling back to created_at for a lead that has never
	// moved. A lead sitting in Contacted for three weeks is not "contacted",
	// it is dying, and today the only signal is a date somebody has to compare
	// against today in their head (FR-18 §5).
	StageDays int `gorm:"->"`
}

// WorkflowLeads returns every open lead with its stage age.
//
// Open only: joined and lost carry no next step and appear in no queue
// (FR-18 §6). assignedTo filters by owner — a numeric user id, the literal
// "unassigned", or "" for everyone.
func (r *Repository) WorkflowLeads(ctx context.Context, assignedTo string) ([]WorkflowRow, error) {
	tc := database.MustGetTenant(ctx)

	q := r.db.WithContext(ctx).
		Table("leads").
		Select(`
			leads.*,
			COALESCE(users.name, '') AS assigned_user_name,
			GREATEST(0, DATE_PART('day', NOW() - COALESCE(sc.last_change, leads.created_at)))::int AS stage_days`).
		Joins("LEFT JOIN users ON users.id = leads.assigned_user_id").
		// LATERAL rather than a GROUP BY over the whole activity table: the
		// row set here is one gym's open leads, and Postgres can use the
		// (lead_id, created_at DESC) index per row instead of aggregating
		// every stage_change the gym has ever recorded.
		Joins(`LEFT JOIN LATERAL (
			SELECT created_at AS last_change
			  FROM lead_activities la
			 WHERE la.lead_id = leads.id AND la.type = 'stage_change'
			 ORDER BY la.created_at DESC
			 LIMIT 1
		) sc ON true`).
		Where(`leads.gym_id = ? AND leads.deleted_at IS NULL
		       AND leads.status NOT IN (?, ?)`,
			tc.GymID(), LeadStatusJoined, LeadStatusLost)

	if assignedTo == "unassigned" {
		q = q.Where("leads.assigned_user_id IS NULL")
	} else if assignedTo != "" {
		if uid, err := strconv.ParseInt(assignedTo, 10, 64); err == nil {
			q = q.Where("leads.assigned_user_id = ?", uid)
		}
	}

	var rows []WorkflowRow
	// Nulls first: a lead with no due date is unattended, and unattended sorts
	// above everything (FR-18 §1).
	err := q.Order("leads.next_step_due ASC NULLS FIRST, leads.created_at ASC").
		Scan(&rows).Error
	return rows, err
}

// SetNextStep records what happens next. Nil clears it, which returns the lead
// to Unattended — a legitimate thing to do deliberately, and visible when it
// happens by accident.
func (r *Repository) SetNextStep(
	ctx context.Context, leadID int64, step *string, due *time.Time,
) error {
	return r.Update(ctx, leadID, map[string]interface{}{
		"next_step":     step,
		"next_step_due": due,
	})
}
