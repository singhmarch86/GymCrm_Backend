package trainers

import (
	"context"
	"errors"
	"time"

	"gorm.io/gorm"

	"gymcrm/internal/database"
)

type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository { return &Repository{db: db} }

func (r *Repository) Create(ctx context.Context, t *Trainer) error {
	return database.ScopedDB(ctx, r.db).Create(t).Error
}

func (r *Repository) FindByID(ctx context.Context, id int64) (*Trainer, error) {
	var t Trainer
	err := database.ScopedDB(ctx, r.db).Where("id = ? AND deleted_at IS NULL", id).Take(&t).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &t, err
}

func (r *Repository) List(ctx context.Context, activeOnly bool) ([]Trainer, error) {
	q := database.ScopedDB(ctx, r.db).Where("deleted_at IS NULL")
	if activeOnly {
		q = q.Where("status = 'active'")
	}
	var out []Trainer
	err := q.Order("first_name, last_name").Find(&out).Error
	return out, err
}

func (r *Repository) Update(ctx context.Context, id int64, mut map[string]any) error {
	mut["updated_at"] = time.Now()
	return database.ScopedDB(ctx, r.db).Table("trainers").Where("id = ?", id).Updates(mut).Error
}
