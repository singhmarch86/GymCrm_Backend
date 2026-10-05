package ptfeedback

import (
	"context"
	"time"

	"gorm.io/gorm"
)

type Repository struct{ db *gorm.DB }

func NewRepository(db *gorm.DB) *Repository { return &Repository{db: db} }

func (r *Repository) Create(ctx context.Context, f *Feedback) error {
	return r.db.WithContext(ctx).Create(f).Error
}

// row shape shared by ByMember and ByTrainer — same joins, different filter.
type row struct {
	ID              int64
	MemberID        int64
	MemberName      string
	AuthorRole      string
	TrainerID       *int64
	TrainerName     *string
	PTPackageID     *int64
	PTAppointmentID *int64
	Note            string
	CreatedByName   string
	CreatedAt       time.Time
}

const selectRows = `
	SELECT f.id, f.member_id,
	       m.first_name || ' ' || m.last_name AS member_name,
	       f.author_role,
	       f.trainer_id,
	       (t.first_name || ' ' || t.last_name) AS trainer_name,
	       f.pt_package_id, f.pt_appointment_id,
	       f.note,
	       COALESCE(u.name, 'Unknown') AS created_by_name,
	       f.created_at
	FROM member_feedback f
	JOIN members m ON m.id = f.member_id
	LEFT JOIN trainers t ON t.id = f.trainer_id
	LEFT JOIN users u ON u.id = f.created_by_user_id`

// ByMember is a member's feedback history, both roles, newest first.
func (r *Repository) ByMember(ctx context.Context, gymID, memberID int64) ([]row, error) {
	var rows []row
	err := r.db.WithContext(ctx).Raw(selectRows+`
		WHERE f.gym_id = ? AND f.member_id = ?
		ORDER BY f.created_at DESC`, gymID, memberID).Scan(&rows).Error
	return rows, err
}

// ByTrainer is every feedback row tied to a trainer, either direction —
// what the trainer observed and what members said about sessions with them —
// newest first. Callers that need only what the trainer authored filter on
// AuthorRole == AuthorTrainer client-side; the trainer-side PT report wants
// both.
func (r *Repository) ByTrainer(ctx context.Context, gymID, trainerID int64) ([]row, error) {
	var rows []row
	err := r.db.WithContext(ctx).Raw(selectRows+`
		WHERE f.gym_id = ? AND f.trainer_id = ?
		ORDER BY f.created_at DESC`, gymID, trainerID).Scan(&rows).Error
	return rows, err
}
