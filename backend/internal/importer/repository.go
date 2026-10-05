package importer

import (
	"context"
	"errors"
	"strings"
	"time"

	"gorm.io/gorm"

	"gymcrm/internal/database"
)

// Repository owns the staging tables and the writes into real tables at commit.
//
// The critical property: nothing in the validation path writes to members,
// membership_plans or payments. Only CommitX methods do, and each row commits
// in its own transaction so one bad row can't roll back seven hundred good
// ones (FR-05 §5.2).
type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository { return &Repository{db: db} }

// ─── Batches ──────────────────────────────────────────────────────────────────

func (r *Repository) CreateBatch(ctx context.Context, b *ImportBatch) error {
	return database.ScopedDB(ctx, r.db).Create(b).Error
}

func (r *Repository) FindBatch(ctx context.Context, id int64) (*ImportBatch, error) {
	var b ImportBatch
	err := database.ScopedDB(ctx, r.db).Where("id = ?", id).Take(&b).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &b, err
}

func (r *Repository) ListBatches(ctx context.Context) ([]ImportBatch, error) {
	var out []ImportBatch
	err := database.ScopedDB(ctx, r.db).Order("created_at DESC").Limit(50).Find(&out).Error
	return out, err
}

func (r *Repository) UpdateBatch(ctx context.Context, id int64, fields map[string]any) error {
	fields["updated_at"] = time.Now()
	return database.ScopedDB(ctx, r.db).Table("import_batches").Where("id = ?", id).Updates(fields).Error
}

// ─── Rows ─────────────────────────────────────────────────────────────────────

func (r *Repository) CreateRows(ctx context.Context, rows []ImportRow) error {
	if len(rows) == 0 {
		return nil
	}
	// Batched insert: a 2,000-member file shouldn't mean 2,000 round trips.
	return database.ScopedDB(ctx, r.db).CreateInBatches(rows, 200).Error
}

func (r *Repository) ListRows(ctx context.Context, batchID int64, status string, limit int) ([]ImportRow, error) {
	q := database.ScopedDB(ctx, r.db).Where("batch_id = ?", batchID)
	if status != "" {
		q = q.Where("status = ?", status)
	}
	if limit > 0 {
		q = q.Limit(limit)
	}
	var out []ImportRow
	err := q.Order("line_number").Find(&out).Error
	return out, err
}

func (r *Repository) UpdateRow(ctx context.Context, id int64, fields map[string]any) error {
	return database.ScopedDB(ctx, r.db).Table("import_rows").Where("id = ?", id).Updates(fields).Error
}

// ─── Lookups used during validation ───────────────────────────────────────────

// existingMemberIDByPhone powers duplicate detection. Phones are compared
// after normalisation on the way in, so +91/0 prefixes don't create phantom
// duplicates.
func (r *Repository) existingMemberIDByPhone(ctx context.Context, phone string) (int64, error) {
	tc := database.MustGetTenant(ctx)
	var id int64
	err := r.db.WithContext(ctx).Table("members").
		Select("id").
		Where("gym_id = ? AND deleted_at IS NULL AND regexp_replace(phone, '[^0-9]', '', 'g') LIKE ?",
			tc.GymID(), "%"+phone).
		Limit(1).Scan(&id).Error
	return id, err
}

func (r *Repository) existingPlanIDByName(ctx context.Context, name string) (int64, error) {
	tc := database.MustGetTenant(ctx)
	var id int64
	err := r.db.WithContext(ctx).Table("membership_plans").
		Select("id").
		Where("gym_id = ? AND deleted_at IS NULL AND LOWER(name) = ?", tc.GymID(), strings.ToLower(strings.TrimSpace(name))).
		Limit(1).Scan(&id).Error
	return id, err
}

// ─── Commit writes ────────────────────────────────────────────────────────────

// Inserts use explicit SQL with RETURNING id: GORM's map-based Create does not
// reliably populate the generated key, and the import needs that id to record
// what each row produced.
func (r *Repository) insertMember(ctx context.Context, m *memberRow) (int64, error) {
	tc := database.MustGetTenant(ctx)
	var id int64
	err := r.db.WithContext(ctx).Raw(`
		INSERT INTO members (gym_id, first_name, last_name, phone, email, gender,
			date_of_birth, address, membership_plan_id, start_date, expiry_date,
			join_date, status, notes, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
			COALESCE(?, ?, CURRENT_DATE), ?, ?, now(), now())
		RETURNING id`,
		tc.GymID(), m.FirstName, m.LastName, m.Phone, m.Email, m.Gender,
		m.DateOfBirth, m.Address, m.PlanID, m.StartDate, m.ExpiryDate,
		// An explicit join date if the file had one, else the term start —
		// for a first import those are the same day. Falling through to
		// CURRENT_DATE would date a ten-year member from the day the gym
		// switched systems, and hide them from At Risk for their first 90
		// days here (FR-10 §4).
		m.JoinDate, m.StartDate,
		m.Status, m.Notes,
	).Scan(&id).Error
	return id, err
}

// updateMember applies an import over an existing member. Status and expiry
// are only touched when the file actually carried those columns — a partial
// spreadsheet must never silently expire a live member (FR-05 §4).
func (r *Repository) updateMember(ctx context.Context, id int64, m *memberRow, hasStatus, hasExpiry bool) error {
	fields := map[string]any{
		"first_name": m.FirstName, "last_name": m.LastName,
		"updated_at": time.Now(),
	}
	if m.Email != nil {
		fields["email"] = m.Email
	}
	if m.Gender != nil {
		fields["gender"] = m.Gender
	}
	if m.DateOfBirth != nil {
		fields["date_of_birth"] = m.DateOfBirth
	}
	if m.Address != nil {
		fields["address"] = m.Address
	}
	if m.PlanID != nil {
		fields["membership_plan_id"] = m.PlanID
	}
	if m.StartDate != nil {
		fields["start_date"] = m.StartDate
	}
	if hasExpiry && m.ExpiryDate != nil {
		fields["expiry_date"] = m.ExpiryDate
	}
	if hasStatus {
		fields["status"] = m.Status
	}
	return database.ScopedDB(ctx, r.db).Table("members").Where("id = ?", id).Updates(fields).Error
}

func (r *Repository) insertPlan(ctx context.Context, p *planRow) (int64, error) {
	tc := database.MustGetTenant(ctx)
	var id int64
	err := r.db.WithContext(ctx).Raw(`
		INSERT INTO membership_plans (gym_id, name, description, duration_days,
			price_in_paise, is_active, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, true, now(), now())
		RETURNING id`,
		tc.GymID(), p.Name, p.Description, p.DurationDays, p.PriceInPaise,
	).Scan(&id).Error
	return id, err
}

func (r *Repository) insertPayment(ctx context.Context, p *paymentRow) (int64, error) {
	tc := database.MustGetTenant(ctx)
	paidDate := p.PaymentDate
	if paidDate == nil {
		now := time.Now()
		paidDate = &now
	}
	var id int64
	err := r.db.WithContext(ctx).Raw(`
		INSERT INTO payments (gym_id, member_id, amount_in_paise, status,
			payment_mode, paid_date, reference_number, notes,
			collected_by_user_id, created_at, updated_at)
		VALUES (?, ?, ?, 'paid', ?, ?, ?, ?, ?, now(), now())
		RETURNING id`,
		tc.GymID(), p.MemberID, p.AmountInPaise, p.PaymentMode, paidDate,
		p.Reference, p.Notes, tc.UserID(),
	).Scan(&id).Error
	return id, err
}
