package branches

import (
	"context"
	"errors"
	"sort"
	"strings"
	"time"

	"gorm.io/gorm"
)

// Repository owns organizations and branch-access grants.
//
// NOTE ON SCOPING: unlike every other repository in this codebase, the methods
// here deliberately do NOT use database.ScopedDB. They exist to answer
// questions *across* gyms ("which branches may this user enter?"), which is
// precisely the question ScopedDB is designed to prevent asking. Every method
// is therefore scoped by user_id instead, and it is the user — never a
// client-supplied gym_id — that bounds the result (FR-06 §1.1).
type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository { return &Repository{db: db} }

// AccessibleBranches lists the branches a user holds a grant for, with the role
// they hold in each. This is the authoritative answer to "where may this user
// work?" and the basis of every access check.
func (r *Repository) AccessibleBranches(ctx context.Context, userID int64) ([]Branch, error) {
	var out []Branch
	err := r.db.WithContext(ctx).
		Table("user_gym_access uga").
		Select(`g.id, g.name, g.branch_name, g.city, g.state, g.status,
		        g.organization_id, uga.role`).
		Joins("JOIN gyms g ON g.id = uga.gym_id").
		Where("uga.user_id = ?", userID).
		Order("g.name").
		Scan(&out).Error
	return out, err
}

// RoleFor returns the user's role in a branch, or "" if they have no grant.
//
// The empty string IS the access denial — callers must treat it as "no", not as
// a default role. This is the check that stands between an authenticated user
// and every other gym's data.
func (r *Repository) RoleFor(ctx context.Context, userID, gymID int64) (string, error) {
	var role string
	err := r.db.WithContext(ctx).
		Table("user_gym_access").
		Select("role").
		Where("user_id = ? AND gym_id = ?", userID, gymID).
		Limit(1).
		Scan(&role).Error
	return role, err
}

// ─── Organizations ────────────────────────────────────────────────────────────

func (r *Repository) FindOrganization(ctx context.Context, id int64) (*Organization, error) {
	var o Organization
	err := r.db.WithContext(ctx).Where("id = ?", id).Take(&o).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &o, err
}

// OrganizationIDForGym is used to keep new branches inside the caller's own
// chain — a user can only ever create a branch in the organization they are
// already in.
func (r *Repository) OrganizationIDForGym(ctx context.Context, gymID int64) (*int64, error) {
	var orgID *int64
	err := r.db.WithContext(ctx).Table("gyms").
		Select("organization_id").Where("id = ?", gymID).
		Limit(1).Scan(&orgID).Error
	return orgID, err
}

func (r *Repository) CreateOrganization(ctx context.Context, name string) (int64, error) {
	var id int64
	err := r.db.WithContext(ctx).Raw(
		`INSERT INTO organizations (name, created_at, updated_at)
		 VALUES (?, now(), now()) RETURNING id`, name).Scan(&id).Error
	return id, err
}

// ─── Branches ─────────────────────────────────────────────────────────────────

// CreateBranch adds a gym inside an organization and grants the creating user
// owner access to it, atomically. Creating a branch you cannot then enter would
// be a trap, and creating one without a grant would orphan it.
func (r *Repository) CreateBranch(ctx context.Context, orgID int64, creatorUserID int64, name, branchName, city, state, phone string) (int64, error) {
	var gymID int64
	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Raw(`
			INSERT INTO gyms (name, owner_name, phone, city, state, status,
				organization_id, branch_name, created_at, updated_at)
			VALUES (?, '', ?, ?, ?, 'active', ?, ?, now(), now())
			RETURNING id`,
			name, phone, city, state, orgID, branchName,
		).Scan(&gymID).Error; err != nil {
			return err
		}
		return tx.Exec(`
			INSERT INTO user_gym_access (user_id, gym_id, role, created_at)
			VALUES (?, ?, 'owner', now())
			ON CONFLICT (user_id, gym_id) DO NOTHING`,
			creatorUserID, gymID).Error
	})
	return gymID, err
}

func (r *Repository) UpdateBranch(ctx context.Context, gymID int64, fields map[string]any) error {
	fields["updated_at"] = time.Now()
	return r.db.WithContext(ctx).Table("gyms").Where("id = ?", gymID).Updates(fields).Error
}

// ─── Grants ───────────────────────────────────────────────────────────────────

// GrantAccess gives a user access to a branch. The caller must already have
// verified that both the target user and the branch belong to the caller's
// organization — this method does not re-check that.
func (r *Repository) GrantAccess(ctx context.Context, userID, gymID int64, role string) error {
	return r.db.WithContext(ctx).Exec(`
		INSERT INTO user_gym_access (user_id, gym_id, role, created_at)
		VALUES (?, ?, ?, now())
		ON CONFLICT (user_id, gym_id) DO UPDATE SET role = EXCLUDED.role`,
		userID, gymID, role).Error
}

func (r *Repository) RevokeAccess(ctx context.Context, userID, gymID int64) error {
	return r.db.WithContext(ctx).
		Exec(`DELETE FROM user_gym_access WHERE user_id = ? AND gym_id = ?`, userID, gymID).Error
}

// UserBelongsToOrganization guards grant management: you may only administer
// users inside your own chain.
func (r *Repository) UserBelongsToOrganization(ctx context.Context, userID, orgID int64) (bool, error) {
	var n int64
	err := r.db.WithContext(ctx).
		Table("users u").
		Joins("JOIN gyms g ON g.id = u.gym_id").
		Where("u.id = ? AND g.organization_id = ?", userID, orgID).
		Count(&n).Error
	return n > 0, err
}

// GymBelongsToOrganization guards branch switching and grant targets.
func (r *Repository) GymBelongsToOrganization(ctx context.Context, gymID, orgID int64) (bool, error) {
	var n int64
	err := r.db.WithContext(ctx).Table("gyms").
		Where("id = ? AND organization_id = ?", gymID, orgID).
		Count(&n).Error
	return n > 0, err
}

// ─── Consolidated reporting ───────────────────────────────────────────────────

// BranchSummary is one branch's headline numbers, for the chain-level view.
//
// Deliberately includes comparison measures, not just totals: raw size mostly
// reflects how long a branch has existed, whereas revenue per member and target
// attainment tell an owner which branch is actually performing.
type BranchSummary struct {
	GymID          int64   `json:"gym_id"`
	Name           string  `json:"name"`
	BranchName     *string `json:"branch_name,omitempty"`
	ActiveMembers  int64   `json:"active_members"`
	TotalMembers   int64   `json:"total_members"`
	ExpiringSoon   int64   `json:"expiring_soon"`
	RevenueInPaise int64   `json:"revenue_this_month_in_paise"`

	NewMembersThisMonth int64 `json:"new_members_this_month"`
	LapsedThisMonth     int64 `json:"lapsed_this_month"`
	RevenueTargetInPaise int64 `json:"monthly_revenue_target_in_paise"`
	MemberTarget         int64 `json:"monthly_member_target"`

	// Computed for display; see toSummaryMetrics.
	RevenuePerMemberInPaise int64   `json:"revenue_per_member_in_paise"`
	RevenueAttainmentPct    float64 `json:"revenue_attainment_pct"`
	MemberAttainmentPct     float64 `json:"member_attainment_pct"`
}

// SummaryForBranches aggregates per branch, bounded to the gym IDs the caller
// was already proven to have access to. The caller passes that list; this
// method never widens it.
func (r *Repository) SummaryForBranches(ctx context.Context, gymIDs []int64) ([]BranchSummary, error) {
	if len(gymIDs) == 0 {
		return []BranchSummary{}, nil
	}
	var out []BranchSummary
	err := r.db.WithContext(ctx).Raw(`
		SELECT g.id AS gym_id, g.name, g.branch_name,
		  g.monthly_revenue_target_in_paise AS revenue_target_in_paise,
		  g.monthly_member_target AS member_target,
		  COALESCE((SELECT count(*) FROM members m
		            WHERE m.gym_id = g.id AND m.deleted_at IS NULL
		              AND m.status = 'active'), 0) AS active_members,
		  COALESCE((SELECT count(*) FROM members m
		            WHERE m.gym_id = g.id AND m.deleted_at IS NULL), 0) AS total_members,
		  COALESCE((SELECT count(*) FROM members m
		            WHERE m.gym_id = g.id AND m.deleted_at IS NULL
		              AND m.expiry_date BETWEEN current_date AND current_date + 30), 0) AS expiring_soon,
		  COALESCE((SELECT count(*) FROM members m
		            WHERE m.gym_id = g.id AND m.deleted_at IS NULL
		              AND m.created_at >= date_trunc('month', current_date)), 0) AS new_members_this_month,
		  COALESCE((SELECT count(*) FROM members m
		            WHERE m.gym_id = g.id AND m.deleted_at IS NULL
		              AND m.expiry_date >= date_trunc('month', current_date)
		              AND m.expiry_date < current_date), 0) AS lapsed_this_month,
		  COALESCE((SELECT sum(p.amount_in_paise) FROM payments p
		            WHERE p.gym_id = g.id AND p.status = 'paid'
		              AND p.paid_date >= date_trunc('month', current_date)), 0) AS revenue_in_paise
		FROM gyms g
		WHERE g.id IN ?
		ORDER BY g.name`, gymIDs).Scan(&out).Error
	if err != nil {
		return nil, err
	}
	for i := range out {
		toSummaryMetrics(&out[i])
	}
	return out, nil
}

// toSummaryMetrics derives the comparison figures. Kept out of SQL so the
// division-by-zero cases are obvious rather than hidden in a NULLIF.
func toSummaryMetrics(b *BranchSummary) {
	if b.ActiveMembers > 0 {
		b.RevenuePerMemberInPaise = b.RevenueInPaise / b.ActiveMembers
	}
	if b.RevenueTargetInPaise > 0 {
		b.RevenueAttainmentPct = float64(b.RevenueInPaise) / float64(b.RevenueTargetInPaise) * 100
	}
	if b.MemberTarget > 0 {
		b.MemberAttainmentPct = float64(b.NewMembersThisMonth) / float64(b.MemberTarget) * 100
	}
}

// SetTargets records what a branch is expected to achieve this month.
func (r *Repository) SetTargets(ctx context.Context, gymID int64, revenueTarget int64, memberTarget int) error {
	return r.db.WithContext(ctx).Table("gyms").Where("id = ?", gymID).
		Updates(map[string]any{
			"monthly_revenue_target_in_paise": revenueTarget,
			"monthly_member_target":           memberTarget,
			"updated_at":                      time.Now(),
		}).Error
}

// ─── Member transfer ──────────────────────────────────────────────────────────

// TransferMember moves a member to another branch and records why.
//
// Only the member record moves. Payments and invoices stay with the branch that
// issued them: that branch recognised the revenue and filed it under its own
// GSTIN, so moving them would rewrite two sets of books (migration 021).
func (r *Repository) TransferMember(ctx context.Context, memberID, fromGymID, toGymID, byUserID int64, reason string) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		res := tx.Table("members").
			Where("id = ? AND gym_id = ? AND deleted_at IS NULL", memberID, fromGymID).
			Updates(map[string]any{"gym_id": toGymID, "updated_at": time.Now()})
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected == 0 {
			return ErrMemberNotInBranch
		}
		return tx.Exec(`
			INSERT INTO member_branch_transfers
			  (member_id, from_gym_id, to_gym_id, reason, transferred_by_user_id, created_at)
			VALUES (?, ?, ?, ?, ?, now())`,
			memberID, fromGymID, toGymID, nullIfEmpty(reason), byUserID).Error
	})
}

// MemberInBranch confirms a member belongs to the branch the caller is acting
// in, before anything is moved.
func (r *Repository) MemberInBranch(ctx context.Context, memberID, gymID int64) (bool, error) {
	var n int64
	err := r.db.WithContext(ctx).Table("members").
		Where("id = ? AND gym_id = ? AND deleted_at IS NULL", memberID, gymID).
		Count(&n).Error
	return n > 0, err
}

// BranchPeriodReport is one branch's performance over an arbitrary period.
//
// The month-to-date summary answers "how are we doing now"; this answers
// "how did each branch do over a period I choose", which is what an owner
// needs for a monthly review or a year-on-year comparison.
type BranchPeriodReport struct {
	GymID      int64   `json:"gym_id"`
	Name       string  `json:"name"`
	BranchName *string `json:"branch_name,omitempty"`

	MembershipRevenueInPaise int64 `json:"membership_revenue_in_paise"`
	RetailRevenueInPaise     int64 `json:"retail_revenue_in_paise"`
	TotalRevenueInPaise      int64 `json:"total_revenue_in_paise"`

	NewMembers      int64 `json:"new_members"`
	ActiveMembers   int64 `json:"active_members"`
	LapsedInPeriod  int64 `json:"lapsed_in_period"`
	PaymentsCount   int64 `json:"payments_count"`

	RevenueTargetInPaise int64   `json:"monthly_revenue_target_in_paise"`
	AttainmentPct        float64 `json:"attainment_pct"`
	RevenuePerMemberInPaise int64 `json:"revenue_per_member_in_paise"`
	// Position in the chain by total revenue, 1 = best.
	Rank int `json:"rank"`
}

// PeriodReport aggregates per branch over a date range, bounded to the gym IDs
// the caller was already proven to hold. Ranking is computed here rather than
// left to the client so every consumer agrees on the order.
func (r *Repository) PeriodReport(ctx context.Context, gymIDs []int64, from, to time.Time) ([]BranchPeriodReport, error) {
	if len(gymIDs) == 0 {
		return []BranchPeriodReport{}, nil
	}
	var out []BranchPeriodReport
	err := r.db.WithContext(ctx).Raw(`
		SELECT g.id AS gym_id, g.name, g.branch_name,
		  g.monthly_revenue_target_in_paise AS revenue_target_in_paise,
		  COALESCE((SELECT sum(p.amount_in_paise) FROM payments p
		            WHERE p.gym_id = g.id AND p.status = 'paid'
		              AND p.paid_date BETWEEN ? AND ?), 0) AS membership_revenue_in_paise,
		  COALESCE((SELECT sum(s.total_in_paise) FROM sales s
		            WHERE s.gym_id = g.id
		              AND s.created_at BETWEEN ? AND ?), 0) AS retail_revenue_in_paise,
		  COALESCE((SELECT count(*) FROM payments p
		            WHERE p.gym_id = g.id AND p.status = 'paid'
		              AND p.paid_date BETWEEN ? AND ?), 0) AS payments_count,
		  COALESCE((SELECT count(*) FROM members m
		            WHERE m.gym_id = g.id AND m.deleted_at IS NULL
		              AND m.created_at BETWEEN ? AND ?), 0) AS new_members,
		  COALESCE((SELECT count(*) FROM members m
		            WHERE m.gym_id = g.id AND m.deleted_at IS NULL
		              AND m.status = 'active'), 0) AS active_members,
		  COALESCE((SELECT count(*) FROM members m
		            WHERE m.gym_id = g.id AND m.deleted_at IS NULL
		              AND m.expiry_date BETWEEN ? AND ?), 0) AS lapsed_in_period
		FROM gyms g
		WHERE g.id IN ?`,
		from, to, from, to, from, to, from, to, from, to, gymIDs,
	).Scan(&out).Error
	if err != nil {
		return nil, err
	}

	for i := range out {
		b := &out[i]
		b.TotalRevenueInPaise = b.MembershipRevenueInPaise + b.RetailRevenueInPaise
		if b.ActiveMembers > 0 {
			b.RevenuePerMemberInPaise = b.TotalRevenueInPaise / b.ActiveMembers
		}
		if b.RevenueTargetInPaise > 0 {
			b.AttainmentPct = float64(b.TotalRevenueInPaise) / float64(b.RevenueTargetInPaise) * 100
		}
	}

	// Rank by revenue, best first — the league table's actual ordering.
	sort.Slice(out, func(i, j int) bool {
		return out[i].TotalRevenueInPaise > out[j].TotalRevenueInPaise
	})
	for i := range out {
		out[i].Rank = i + 1
	}
	return out, nil
}

// TransferStaff moves a user's home branch and guarantees they hold a grant
// there, atomically — moving someone into a branch they cannot enter would
// simply lock them out.
//
// The grant at the branch they came from is deliberately left in place: staff
// covering shifts at their old location is normal, and revoking access is a
// separate, explicit action.
func (r *Repository) TransferStaff(ctx context.Context, userID, toGymID int64, role string) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		res := tx.Table("users").Where("id = ?", userID).
			Updates(map[string]any{"gym_id": toGymID, "updated_at": time.Now()})
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected == 0 {
			return ErrUserNotFound
		}
		return tx.Exec(`
			INSERT INTO user_gym_access (user_id, gym_id, role, created_at)
			VALUES (?, ?, ?, now())
			ON CONFLICT (user_id, gym_id) DO UPDATE SET role = EXCLUDED.role`,
			userID, toGymID, role).Error
	})
}

// TransferTrainer moves a trainer's roster record to another branch.
//
// PT packages and appointments already sold stay with the branch that sold
// them — they are that branch's revenue and its members' entitlements. Because
// package queries resolve the trainer's name by id rather than by branch, the
// history stays readable after the move; only NEW packages follow the trainer.
func (r *Repository) TransferTrainer(ctx context.Context, trainerID, fromGymID, toGymID int64) error {
	res := r.db.WithContext(ctx).Table("trainers").
		Where("id = ? AND gym_id = ? AND deleted_at IS NULL", trainerID, fromGymID).
		Updates(map[string]any{"gym_id": toGymID, "updated_at": time.Now()})
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected == 0 {
		return ErrTrainerNotInBranch
	}
	return nil
}

// UserExists guards staff transfer before anything is moved.
func (r *Repository) UserInOrganization(ctx context.Context, userID, orgID int64) (bool, error) {
	return r.UserBelongsToOrganization(ctx, userID, orgID)
}

func nullIfEmpty(s string) any {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	return s
}
