package lifecycle

import (
	"context"
	"errors"
	"time"

	"gorm.io/gorm"

	"gymcrm/internal/database"
)

// Repository handles all lifecycle DB operations.
//
// TENANT ISOLATION:
//  1. Every query starts from database.ScopedDB(ctx, r.db)
//  2. Joined queries qualify gym_id as "membership_events.gym_id"
//  3. No Update or Delete on membership_events — the table is append-only
//
// TRANSACTIONS:
// Unlike renewals (which does its two writes sequentially and documents the
// risk), every lifecycle operation wraps the event insert and the member update
// in a real DB transaction. These operations change a member's status and
// expiry; a half-applied freeze — event written, member not updated, or vice
// versa — is materially worse than a half-applied renewal, because the member
// row is what gates door access and check-in.
type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository {
	return &Repository{db: db}
}

func (r *Repository) scopedEventsDB(ctx context.Context) *gorm.DB {
	tc := database.MustGetTenant(ctx)
	return r.db.WithContext(ctx).Where("membership_events.gym_id = ?", tc.GymID())
}

// ─── Reads ────────────────────────────────────────────────────────────────────

// FindMember loads the lifecycle-relevant subset of a member.
// Returns (nil, nil) when not found — callers map that to ErrMemberNotFound.
func (r *Repository) FindMember(ctx context.Context, id int64) (*memberSnapshot, error) {
	var m memberSnapshot
	err := database.ScopedDB(ctx, r.db).
		Table("members").
		Select(`id, gym_id, first_name, last_name, status, membership_plan_id,
		        start_date, expiry_date, join_date, frozen_from, frozen_until,
		        COALESCE(freeze_days_used_ytd, 0) AS freeze_days_used_ytd,
		        freeze_year_start`).
		Where("id = ? AND deleted_at IS NULL", id).
		Take(&m).Error

	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &m, nil
}

// FindPlan loads the pricing subset of a membership plan.
func (r *Repository) FindPlan(ctx context.Context, id int64) (*planSnapshot, error) {
	var p planSnapshot
	err := database.ScopedDB(ctx, r.db).
		Table("membership_plans").
		Select("id, name, price_in_paise, duration_days, is_active").
		Where("id = ? AND deleted_at IS NULL", id).
		Take(&p).Error

	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &p, nil
}

// eventRow is the denormalised read model for a lifecycle event — the event
// plus the names the UI needs, resolved in one query rather than N+1.
type eventRow struct {
	MembershipEvent
	MemberName          string
	OldPlanName         *string
	NewPlanName         *string
	RelatedMemberName   *string
	PerformedByUserName string
}

// ListMemberEvents returns a member's lifecycle timeline, newest first.
func (r *Repository) ListMemberEvents(ctx context.Context, memberID int64) ([]eventRow, error) {
	var rows []eventRow
	err := r.scopedEventsDB(ctx).
		Table("membership_events").
		Select(`membership_events.*,
		        m.first_name || ' ' || m.last_name        AS member_name,
		        op.name                                    AS old_plan_name,
		        np.name                                    AS new_plan_name,
		        rm.first_name || ' ' || rm.last_name       AS related_member_name,
		        COALESCE(u.name, 'Unknown')                AS performed_by_user_name`).
		Joins("JOIN members m ON m.id = membership_events.member_id").
		Joins("LEFT JOIN membership_plans op ON op.id = membership_events.old_plan_id").
		Joins("LEFT JOIN membership_plans np ON np.id = membership_events.new_plan_id").
		Joins("LEFT JOIN members rm ON rm.id = membership_events.related_member_id").
		Joins("LEFT JOIN users u ON u.id = membership_events.performed_by_user_id").
		Where("membership_events.member_id = ?", memberID).
		Order("membership_events.effective_date DESC, membership_events.id DESC").
		Scan(&rows).Error

	return rows, err
}

// ─── Writes ───────────────────────────────────────────────────────────────────

// memberMutation is the set of member columns a lifecycle operation may change.
// Using an explicit map rather than a struct save means we never accidentally
// write a zero value over a column this operation had no business touching.
type memberMutation map[string]any

// ApplyEvent inserts the audit event and applies the member mutation inside one
// transaction. Either both land or neither does.
func (r *Repository) ApplyEvent(ctx context.Context, ev *MembershipEvent, memberID int64, mut memberMutation) error {
	tc := database.MustGetTenant(ctx)

	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(ev).Error; err != nil {
			return err
		}
		if len(mut) == 0 {
			return nil
		}
		mut["updated_at"] = time.Now()
		return tx.Table("members").
			Where("id = ? AND gym_id = ? AND deleted_at IS NULL", memberID, tc.GymID()).
			Updates(map[string]any(mut)).Error
	})
}

// ApplyTransfer writes both halves of a transfer and mutates both members in one
// transaction. A transfer that half-applies would either duplicate a membership
// or destroy one, so this must be atomic.
func (r *Repository) ApplyTransfer(
	ctx context.Context,
	outEvent, inEvent *MembershipEvent,
	sourceID int64, sourceMut memberMutation,
	targetID int64, targetMut memberMutation,
) error {
	tc := database.MustGetTenant(ctx)
	now := time.Now()

	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(outEvent).Error; err != nil {
			return err
		}
		if err := tx.Create(inEvent).Error; err != nil {
			return err
		}

		sourceMut["updated_at"] = now
		if err := tx.Table("members").
			Where("id = ? AND gym_id = ? AND deleted_at IS NULL", sourceID, tc.GymID()).
			Updates(map[string]any(sourceMut)).Error; err != nil {
			return err
		}

		targetMut["updated_at"] = now
		return tx.Table("members").
			Where("id = ? AND gym_id = ? AND deleted_at IS NULL", targetID, tc.GymID()).
			Updates(map[string]any(targetMut)).Error
	})
}

// ThawExpiredFreezes clears the frozen state of any member whose freeze window
// has passed, returning them to active.
//
// Auto-thaw is computed on read (see memberSnapshot.isEffectivelyFrozen), so
// this is a housekeeping convenience rather than a correctness requirement —
// the system is correct whether or not it ever runs.
func (r *Repository) ThawExpiredFreezes(ctx context.Context) (int64, error) {
	res := database.ScopedDB(ctx, r.db).
		Table("members").
		Where("status = ? AND frozen_until IS NOT NULL AND frozen_until < CURRENT_DATE AND deleted_at IS NULL", StatusFrozen).
		Updates(map[string]any{
			"status":       StatusActive,
			"frozen_from":  nil,
			"frozen_until": nil,
			"updated_at":   time.Now(),
		})
	return res.RowsAffected, res.Error
}
