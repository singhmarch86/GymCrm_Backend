package users

import (
	"context"
	"errors"
	"strings"

	"gorm.io/gorm"

	"gymcrm/internal/database"
)

type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository {
	return &Repository{db: db}
}

// StaffRow is a user plus the workload figure the UI needs, so the staff list
// and the lead-assignee picker can be served from one query.
type StaffRow struct {
	ID        int64  `json:"id"`
	GymID     int64  `json:"gym_id"`
	Name      string `json:"name"`
	Phone     string `json:"phone"`
	Email     string `json:"email"`
	Role      string `json:"role"`
	Status    string `json:"status"`
	LeadCount int64  `json:"lead_count"` // open leads currently assigned
	CreatedAt string `json:"created_at"`
}

// List returns every user in the gym. Inactive users are included — the UI
// shows them greyed out so a deactivated trainer who still owns leads stays
// visible rather than silently vanishing.
func (r *Repository) List(ctx context.Context) ([]StaffRow, error) {
	tc := database.MustGetTenant(ctx)
	var out []StaffRow
	err := r.db.WithContext(ctx).Raw(`
		SELECT
			u.id, u.gym_id, u.name, u.phone,
			COALESCE(u.email, '') AS email,
			u.role, u.status,
			COUNT(l.id) FILTER (
				WHERE l.deleted_at IS NULL
				  AND l.status NOT IN ('joined','lost')
			) AS lead_count,
			u.created_at
		FROM users u
		LEFT JOIN leads l ON l.assigned_user_id = u.id
		WHERE u.gym_id = ?
		GROUP BY u.id, u.gym_id, u.name, u.phone, u.email, u.role, u.status, u.created_at
		ORDER BY
			CASE WHEN u.status = 'active' THEN 0 ELSE 1 END,
			u.name ASC
	`, tc.GymID()).Scan(&out).Error
	return out, err
}

func (r *Repository) FindByID(ctx context.Context, id int64) (*User, error) {
	var u User
	err := database.ScopedDB(ctx, r.db).Where("id = ?", id).First(&u).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &u, nil
}

// PhoneExistsInGym guards the login identity. Phone is how users sign in, so a
// duplicate inside one gym would make the account ambiguous.
func (r *Repository) PhoneExistsInGym(ctx context.Context, phone string, excludeID int64) (bool, error) {
	tc := database.MustGetTenant(ctx)
	q := r.db.WithContext(ctx).
		Model(&User{}).
		Where("gym_id = ? AND phone = ?", tc.GymID(), strings.TrimSpace(phone))
	if excludeID > 0 {
		q = q.Where("id <> ?", excludeID)
	}
	var count int64
	if err := q.Count(&count).Error; err != nil {
		return false, err
	}
	return count > 0, nil
}

// PhoneExistsAnywhere mirrors how login resolves an account. Login looks a user
// up by phone across the whole table, so a phone reused in another gym would
// make sign-in ambiguous even though the per-gym check passes.
func (r *Repository) PhoneExistsAnywhere(ctx context.Context, phone string, excludeID int64) (bool, error) {
	q := r.db.WithContext(ctx).
		Model(&User{}).
		Where("phone = ?", strings.TrimSpace(phone))
	if excludeID > 0 {
		q = q.Where("id <> ?", excludeID)
	}
	var count int64
	if err := q.Count(&count).Error; err != nil {
		return false, err
	}
	return count > 0, nil
}

func (r *Repository) Create(ctx context.Context, u *User) error {
	tc := database.MustGetTenant(ctx)
	u.GymID = tc.GymID()
	return r.db.WithContext(ctx).Create(u).Error
}

func (r *Repository) Update(ctx context.Context, id int64, updates map[string]interface{}) error {
	return database.ScopedDB(ctx, r.db).
		Model(&User{}).
		Where("id = ?", id).
		Updates(updates).Error
}

// CountActiveOwners backs the "don't lock yourself out" guard — a gym must
// always retain at least one active owner.
func (r *Repository) CountActiveOwners(ctx context.Context, excludeID int64) (int64, error) {
	tc := database.MustGetTenant(ctx)
	q := r.db.WithContext(ctx).
		Model(&User{}).
		Where("gym_id = ? AND role = ? AND status = ?", tc.GymID(), RoleOwner, UserStatusActive)
	if excludeID > 0 {
		q = q.Where("id <> ?", excludeID)
	}
	var count int64
	err := q.Count(&count).Error
	return count, err
}
