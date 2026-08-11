package members

import (
	"context"
	"strings"
	"time"

	"gymcrm/internal/database"
	"gymcrm/internal/shared/pagination"
)

// DetailRow is a member plus the two things a table needs that the members
// table itself does not hold (FR-17 §2).
type DetailRow struct {
	Member
	MembershipPlanName *string    `gorm:"->"`
	LastVisitAt        *time.Time `gorm:"->"`
}

// ListDetailed is List plus plan name and last visit, resolved in one query.
//
// ToResponseList deliberately passes an empty plan name to avoid N+1 lookups —
// a sound decision that left `membership_plan_name` declared in the response
// and never populated. The fix is a JOIN, not per-row lookups: the field is
// either resolved for everybody or should not be advertised at all.
//
// last_visit_at is a LATERAL against attendance, which is the largest table in
// the system — 16,510 rows in the demo and far more in a real gym. It runs
// against the page being returned, never the whole member list, so the cost
// scales with the 30 rows on screen rather than with 809 members.
func (r *Repository) ListDetailed(
	ctx context.Context, params ListMembersRequest,
) ([]DetailRow, int64, error) {
	tc := database.MustGetTenant(ctx)
	p := pagination.Params{
		Page:    params.Page,
		PerPage: params.PerPage,
		Offset:  (params.Page - 1) * params.PerPage,
	}

	base := r.db.WithContext(ctx).
		Table("members").
		Where("members.gym_id = ? AND members.deleted_at IS NULL", tc.GymID())

	if params.Status != "" {
		base = base.Where("members.status = ?", params.Status)
	}
	if params.Search != "" {
		term := "%" + strings.TrimSpace(params.Search) + "%"
		base = base.Where(
			"members.first_name ILIKE ? OR members.last_name ILIKE ? OR members.phone LIKE ?",
			term, term, term,
		)
	}

	// Counted before the joins are added: the LATERAL is per-row work that a
	// COUNT would pay for and then discard.
	var total int64
	if err := base.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var rows []DetailRow
	err := base.
		Select(`members.*, mp.name AS membership_plan_name, av.last_visit_at`).
		Joins("LEFT JOIN membership_plans mp ON mp.id = members.membership_plan_id").
		Joins(`LEFT JOIN LATERAL (
			SELECT MAX(a.checked_in_at) AS last_visit_at
			  FROM attendance a
			 WHERE a.member_id = members.id AND a.gym_id = members.gym_id
		) av ON true`).
		Order("members.created_at DESC").
		Limit(p.PerPage).
		Offset(p.Offset).
		Scan(&rows).Error

	return rows, total, err
}
