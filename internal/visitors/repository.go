package visitors

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

func (r *Repository) Create(ctx context.Context, v *Visitor) error {
	return database.ScopedDB(ctx, r.db).Create(v).Error
}

func (r *Repository) FindByID(ctx context.Context, id int64) (*Visitor, error) {
	var v Visitor
	err := database.ScopedDB(ctx, r.db).Where("id = ?", id).Take(&v).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &v, err
}

func (r *Repository) CheckOut(ctx context.Context, id int64) error {
	return database.ScopedDB(ctx, r.db).
		Table("visitors").Where("id = ?", id).
		Updates(map[string]any{"checked_out_at": time.Now(), "updated_at": time.Now()}).Error
}

func (r *Repository) SetConvertedLead(ctx context.Context, id, leadID int64) error {
	return database.ScopedDB(ctx, r.db).
		Table("visitors").Where("id = ?", id).
		Updates(map[string]any{"converted_lead_id": leadID, "updated_at": time.Now()}).Error
}

type visitorRow struct {
	Visitor
	HostStaffName *string
}

// List returns visits in a date range, newest first, with the host staff
// name resolved so the front-desk screen never has to do a second lookup.
func (r *Repository) List(ctx context.Context, from, to time.Time) ([]visitorRow, error) {
	tc := database.MustGetTenant(ctx)
	var rows []visitorRow
	err := r.db.WithContext(ctx).
		Table("visitors").
		Select(`visitors.*, u.name AS host_staff_name`).
		Joins("LEFT JOIN users u ON u.id = visitors.host_staff_user_id").
		Where("visitors.gym_id = ? AND visitors.checked_in_at BETWEEN ? AND ?", tc.GymID(), from, to).
		Order("visitors.checked_in_at DESC").
		Scan(&rows).Error
	return rows, err
}

func (r *Repository) rowByID(ctx context.Context, id int64) (*visitorRow, error) {
	tc := database.MustGetTenant(ctx)
	var row visitorRow
	err := r.db.WithContext(ctx).
		Table("visitors").
		Select(`visitors.*, u.name AS host_staff_name`).
		Joins("LEFT JOIN users u ON u.id = visitors.host_staff_user_id").
		Where("visitors.id = ? AND visitors.gym_id = ?", id, tc.GymID()).
		Take(&row).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &row, err
}
