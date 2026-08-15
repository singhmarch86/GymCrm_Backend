package recognition

import (
	"context"
	"time"

	"gorm.io/gorm"
)

type Repository struct{ db *gorm.DB }

func NewRepository(db *gorm.DB) *Repository { return &Repository{db: db} }

func (r *Repository) Create(ctx context.Context, rec *Recognition) error {
	return r.db.WithContext(ctx).Create(rec).Error
}

type row struct {
	ID            int64
	MemberID      int64
	Reason        string
	SignalType    *string
	SignalID      *int64
	CreatedByName string
	CreatedAt     time.Time
}

// ByMember is a member's recognition history, newest first.
func (r *Repository) ByMember(ctx context.Context, gymID, memberID int64) ([]row, error) {
	var rows []row
	err := r.db.WithContext(ctx).Raw(`
		SELECT rec.id, rec.member_id, rec.reason, rec.signal_type, rec.signal_id,
		       COALESCE(u.name, 'Unknown') AS created_by_name,
		       rec.created_at
		FROM member_recognitions rec
		LEFT JOIN users u ON u.id = rec.created_by_user_id
		WHERE rec.gym_id = ? AND rec.member_id = ?
		ORDER BY rec.created_at DESC`, gymID, memberID).Scan(&rows).Error
	return rows, err
}
