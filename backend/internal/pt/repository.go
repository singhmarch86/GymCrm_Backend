package pt

import (
	"context"
	"errors"
	"time"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"gymcrm/internal/database"
)

// Repository handles PT package and appointment DB operations.
//
// CONCURRENCY: completing an appointment reads-then-writes the package's
// sessions_used, which is exactly the kind of check-then-act that races if
// two staff complete two appointments against the same package at once. The
// package row is locked FOR UPDATE inside the same transaction as the
// appointment update — same pattern as classes' booking capacity check.
type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository { return &Repository{db: db} }

func (r *Repository) DB() *gorm.DB { return r.db }

// ─── Packages ─────────────────────────────────────────────────────────────────

func (r *Repository) CreatePackage(ctx context.Context, p *Package) error {
	return database.ScopedDB(ctx, r.db).Create(p).Error
}

func (r *Repository) FindPackage(ctx context.Context, id int64) (*Package, error) {
	var p Package
	err := database.ScopedDB(ctx, r.db).Where("id = ?", id).Take(&p).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &p, err
}

func (r *Repository) UpdatePackageStatus(ctx context.Context, id int64, status string) error {
	return database.ScopedDB(ctx, r.db).Table("pt_packages").Where("id = ?", id).
		Updates(map[string]any{"status": status, "updated_at": time.Now()}).Error
}

type packageRow struct {
	Package
	MemberName  string
	TrainerName string
}

func (r *Repository) ListPackages(ctx context.Context, memberID, trainerID *int64) ([]packageRow, error) {
	tc := database.MustGetTenant(ctx)
	q := r.db.WithContext(ctx).
		Table("pt_packages").
		Select(`pt_packages.*,
		        m.first_name || ' ' || m.last_name AS member_name,
		        t.first_name || ' ' || t.last_name AS trainer_name`).
		Joins("JOIN members m ON m.id = pt_packages.member_id").
		Joins("JOIN trainers t ON t.id = pt_packages.trainer_id").
		Where("pt_packages.gym_id = ?", tc.GymID())
	if memberID != nil {
		q = q.Where("pt_packages.member_id = ?", *memberID)
	}
	if trainerID != nil {
		q = q.Where("pt_packages.trainer_id = ?", *trainerID)
	}
	var rows []packageRow
	err := q.Order("pt_packages.created_at DESC").Scan(&rows).Error
	return rows, err
}

func (r *Repository) packageRowByID(ctx context.Context, id int64) (*packageRow, error) {
	tc := database.MustGetTenant(ctx)
	var row packageRow
	err := r.db.WithContext(ctx).
		Table("pt_packages").
		Select(`pt_packages.*,
		        m.first_name || ' ' || m.last_name AS member_name,
		        t.first_name || ' ' || t.last_name AS trainer_name`).
		Joins("JOIN members m ON m.id = pt_packages.member_id").
		Joins("JOIN trainers t ON t.id = pt_packages.trainer_id").
		Where("pt_packages.id = ? AND pt_packages.gym_id = ?", id, tc.GymID()).
		Take(&row).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &row, err
}

// findPackageForUpdate locks the package row inside a transaction — used only
// by CompleteAppointment, where sessions_used is read then incremented.
func (r *Repository) findPackageForUpdate(ctx context.Context, tx *gorm.DB, id int64) (*Package, error) {
	tc := database.MustGetTenant(ctx)
	var p Package
	err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("id = ? AND gym_id = ?", id, tc.GymID()).Take(&p).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &p, err
}

// ─── Appointments ─────────────────────────────────────────────────────────────

func (r *Repository) CreateAppointment(ctx context.Context, a *Appointment) error {
	return database.ScopedDB(ctx, r.db).Create(a).Error
}

func (r *Repository) FindAppointment(ctx context.Context, id int64) (*Appointment, error) {
	var a Appointment
	err := database.ScopedDB(ctx, r.db).Where("id = ?", id).Take(&a).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &a, err
}

type appointmentRow struct {
	Appointment
	TrainerName string
	MemberName  string
}

func (r *Repository) ListAppointments(ctx context.Context, from, to time.Time, trainerID, memberID *int64) ([]appointmentRow, error) {
	tc := database.MustGetTenant(ctx)
	q := r.db.WithContext(ctx).
		Table("pt_appointments").
		Select(`pt_appointments.*,
		        t.first_name || ' ' || t.last_name AS trainer_name,
		        m.first_name || ' ' || m.last_name AS member_name`).
		Joins("JOIN trainers t ON t.id = pt_appointments.trainer_id").
		Joins("JOIN members m ON m.id = pt_appointments.member_id").
		Where("pt_appointments.gym_id = ? AND pt_appointments.scheduled_at BETWEEN ? AND ?", tc.GymID(), from, to)
	if trainerID != nil {
		q = q.Where("pt_appointments.trainer_id = ?", *trainerID)
	}
	if memberID != nil {
		q = q.Where("pt_appointments.member_id = ?", *memberID)
	}
	var rows []appointmentRow
	err := q.Order("pt_appointments.scheduled_at").Scan(&rows).Error
	return rows, err
}

func (r *Repository) appointmentRowByID(ctx context.Context, id int64) (*appointmentRow, error) {
	tc := database.MustGetTenant(ctx)
	var row appointmentRow
	err := r.db.WithContext(ctx).
		Table("pt_appointments").
		Select(`pt_appointments.*,
		        t.first_name || ' ' || t.last_name AS trainer_name,
		        m.first_name || ' ' || m.last_name AS member_name`).
		Joins("JOIN trainers t ON t.id = pt_appointments.trainer_id").
		Joins("JOIN members m ON m.id = pt_appointments.member_id").
		Where("pt_appointments.id = ? AND pt_appointments.gym_id = ?", id, tc.GymID()).
		Take(&row).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &row, err
}

func (r *Repository) SetAppointmentStatus(ctx context.Context, id int64, status string) error {
	return database.ScopedDB(ctx, r.db).Table("pt_appointments").Where("id = ?", id).
		Updates(map[string]any{"status": status, "updated_at": time.Now()}).Error
}

// CompleteAppointmentAndConsumeCredit marks the appointment completed and
// increments the package's sessions_used, atomically. Fails if the package
// has no sessions remaining — the one guard in this whole module that
// actually blocks an action. FR-03 §3.
func (r *Repository) CompleteAppointmentAndConsumeCredit(ctx context.Context, appointmentID, packageID int64) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		pkg, err := r.findPackageForUpdate(ctx, tx, packageID)
		if err != nil {
			return err
		}
		if pkg == nil {
			return ErrPackageNotFound
		}
		if pkg.SessionsUsed >= pkg.TotalSessions {
			return ErrPackageExhausted
		}
		if err := tx.Table("pt_packages").Where("id = ?", packageID).
			Updates(map[string]any{"sessions_used": pkg.SessionsUsed + 1, "updated_at": time.Now()}).Error; err != nil {
			return err
		}
		return tx.Table("pt_appointments").Where("id = ?", appointmentID).
			Updates(map[string]any{"status": AppointmentCompleted, "updated_at": time.Now()}).Error
	})
}
