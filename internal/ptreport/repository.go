package ptreport

import (
	"context"
	"time"

	"gorm.io/gorm"
)

type Repository struct{ db *gorm.DB }

func NewRepository(db *gorm.DB) *Repository { return &Repository{db: db} }

// ─── Member side ────────────────────────────────────────────────────────────

func (r *Repository) MemberPackages(ctx context.Context, gymID, memberID int64) ([]PackageSummary, error) {
	var rows []PackageSummary
	err := r.db.WithContext(ctx).Raw(`
		SELECT p.id, p.trainer_id,
		       t.first_name || ' ' || t.last_name AS trainer_name,
		       p.package_name, p.total_sessions, p.sessions_used,
		       (p.total_sessions - p.sessions_used) AS sessions_remaining,
		       p.status, p.expiry_date
		FROM pt_packages p
		JOIN trainers t ON t.id = p.trainer_id
		WHERE p.gym_id = ? AND p.member_id = ?
		ORDER BY p.created_at DESC`, gymID, memberID).Scan(&rows).Error
	return rows, err
}

func (r *Repository) RhythmSummary(ctx context.Context, gymID, memberID int64) (*RhythmSummary, error) {
	var rows []RhythmSummary
	err := r.db.WithContext(ctx).Raw(`
		SELECT recent_consistency, recent_rate, is_broken
		FROM member_rhythm_profiles
		WHERE gym_id = ? AND member_id = ?`, gymID, memberID).Scan(&rows).Error
	if err != nil || len(rows) == 0 {
		return nil, err
	}
	return &rows[0], nil
}

// ─── Trainer side ───────────────────────────────────────────────────────────

func (r *Repository) SessionsCompleted(ctx context.Context, gymID, trainerID int64) (int, error) {
	var n int64
	err := r.db.WithContext(ctx).Table("pt_appointments").
		Where("gym_id = ? AND trainer_id = ? AND status = 'completed'", gymID, trainerID).
		Count(&n).Error
	return int(n), err
}

// AssignedMembers is every member with an active package under this trainer,
// ordered by name — never by a performance figure (FR-13 §1).
func (r *Repository) AssignedMembers(ctx context.Context, gymID, trainerID int64) ([]MemberRef, error) {
	var rows []MemberRef
	err := r.db.WithContext(ctx).Raw(`
		SELECT DISTINCT m.id, m.first_name || ' ' || m.last_name AS name
		FROM pt_packages p
		JOIN members m ON m.id = p.member_id
		WHERE p.gym_id = ? AND p.trainer_id = ? AND p.status = 'active'
		ORDER BY name`, gymID, trainerID).Scan(&rows).Error
	return rows, err
}

type lastPayout struct {
	TotalInPaise int64
	PeriodEnd    time.Time
}

func (r *Repository) LastPayout(ctx context.Context, gymID, trainerID int64) (*lastPayout, error) {
	var rows []lastPayout
	err := r.db.WithContext(ctx).Raw(`
		SELECT total_in_paise, period_end
		FROM trainer_payouts
		WHERE gym_id = ? AND trainer_id = ? AND status = 'paid'
		ORDER BY period_end DESC
		LIMIT 1`, gymID, trainerID).Scan(&rows).Error
	if err != nil || len(rows) == 0 {
		return nil, err
	}
	return &rows[0], nil
}
