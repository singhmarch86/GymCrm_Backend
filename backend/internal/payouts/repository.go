package payouts

import (
	"context"
	"time"

	"gorm.io/gorm"

	"gymcrm/internal/database"
)

type Repository struct{ db *gorm.DB }

func NewRepository(db *gorm.DB) *Repository { return &Repository{db: db} }

type trainerPay struct {
	ID                int64
	Name              string
	SalaryInPaise     *int64
	CommissionPct     *float64
	PerSessionInPaise *int64
}

func (r *Repository) Trainer(ctx context.Context, id int64) (*trainerPay, error) {
	tc := database.MustGetTenant(ctx)

	var row trainerPay
	err := r.db.WithContext(ctx).Raw(`
		SELECT id,
		       TRIM(first_name || ' ' || COALESCE(last_name, '')) AS name,
		       salary_in_paise, commission_pct, per_session_in_paise
		  FROM trainers
		 WHERE id = ? AND gym_id = ? AND deleted_at IS NULL`,
		id, tc.GymID()).Scan(&row).Error
	if err != nil {
		return nil, err
	}
	if row.ID == 0 {
		return nil, ErrTrainerNotFound
	}
	return &row, nil
}

type commissionRow struct {
	PackageID   int64
	PackageName string
	Member      string
	PaidInPaise int64
	PaidDate    *time.Time
}

// CommissionBase returns PT money the gym was actually PAID inside the period.
//
// Driven off payments, not packages. A package created in the period earns the
// trainer nothing until somebody pays for it; a package sold last year earns
// commission the month its money arrives. Paying on creation would hand a
// trainer a percentage of revenue that may never turn up.
func (r *Repository) CommissionBase(
	ctx context.Context, trainerID int64, from, to string,
) ([]commissionRow, error) {
	tc := database.MustGetTenant(ctx)

	var rows []commissionRow
	err := r.db.WithContext(ctx).Raw(`
		SELECT pk.id AS package_id,
		       pk.package_name,
		       TRIM(m.first_name || ' ' || COALESCE(m.last_name, '')) AS member,
		       p.amount_in_paise AS paid_in_paise,
		       p.paid_date
		  FROM payments p
		  JOIN pt_packages pk ON pk.id = p.pt_package_id
		  JOIN members m ON m.id = pk.member_id
		 WHERE p.gym_id = @gym
		   AND pk.trainer_id = @trainer
		   AND p.status = 'paid'
		   AND p.paid_date BETWEEN CAST(@from AS date) AND CAST(@to AS date)
		 ORDER BY p.paid_date, pk.id`,
		map[string]interface{}{
			"gym": tc.GymID(), "trainer": trainerID, "from": from, "to": to,
		}).Scan(&rows).Error
	return rows, err
}

// UncollectedPT is PT sold by this trainer that the gym has not been paid for.
//
// Not part of the payout — it is the reason a figure looks lower than the
// trainer expected, and the argument for chasing the due. Reported so the
// conversation happens with the number in front of both people.
func (r *Repository) UncollectedPT(
	ctx context.Context, trainerID int64,
) (int64, int, error) {
	tc := database.MustGetTenant(ctx)

	var out struct {
		Amount int64
		N      int
	}
	err := r.db.WithContext(ctx).Raw(`
		SELECT COALESCE(SUM(pk.amount_in_paise), 0) AS amount, COUNT(*) AS n
		  FROM pt_packages pk
		 WHERE pk.gym_id = ?
		   AND pk.trainer_id = ?
		   AND pk.status <> 'cancelled'
		   AND NOT EXISTS (
		       SELECT 1 FROM payments p
		        WHERE p.pt_package_id = pk.id AND p.status = 'paid'
		   )`, tc.GymID(), trainerID).Scan(&out).Error
	return out.Amount, out.N, err
}

type sessionRow struct {
	AppointmentID int64
	Member        string
	ScheduledAt   time.Time
}

// SessionsDelivered counts what the trainer actually ran in the period.
//
// Completed only. A no-show or a cancellation is not delivery, and paying for
// one turns the per-session scheme into a booking bonus.
func (r *Repository) SessionsDelivered(
	ctx context.Context, trainerID int64, from, to string,
) ([]sessionRow, error) {
	tc := database.MustGetTenant(ctx)

	var rows []sessionRow
	err := r.db.WithContext(ctx).Raw(`
		SELECT a.id AS appointment_id,
		       TRIM(m.first_name || ' ' || COALESCE(m.last_name, '')) AS member,
		       a.scheduled_at
		  FROM pt_appointments a
		  JOIN members m ON m.id = a.member_id
		 WHERE a.gym_id = @gym
		   AND a.trainer_id = @trainer
		   AND a.status = 'completed'
		   AND a.scheduled_at::date BETWEEN CAST(@from AS date) AND CAST(@to AS date)
		 ORDER BY a.scheduled_at`,
		map[string]interface{}{
			"gym": tc.GymID(), "trainer": trainerID, "from": from, "to": to,
		}).Scan(&rows).Error
	return rows, err
}

// LivePayoutExists reports whether the period is already covered.
func (r *Repository) LivePayoutExists(
	ctx context.Context, trainerID int64, from, to string,
) (bool, error) {
	tc := database.MustGetTenant(ctx)

	var n int64
	err := r.db.WithContext(ctx).Table("trainer_payouts").
		Where(`gym_id = ? AND trainer_id = ? AND period_start = CAST(? AS date)
		       AND period_end = CAST(? AS date) AND status <> 'cancelled'`,
			tc.GymID(), trainerID, from, to).
		Count(&n).Error
	return n > 0, err
}

// Create writes the payout and its lines in one transaction.
//
// A total without its lines is a number nobody can check — not the owner
// approving it, not the trainer accepting it — so neither is allowed to exist
// without the other.
func (r *Repository) Create(
	ctx context.Context, p *Payout, lines []PayoutLine,
) (int64, error) {
	tc := database.MustGetTenant(ctx)

	var id int64
	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		row := tx.Raw(`
			INSERT INTO trainer_payouts
			    (gym_id, trainer_id, period_start, period_end,
			     salary_in_paise, commission_in_paise, sessions_in_paise,
			     adjustment_in_paise, adjustment_reason, total_in_paise,
			     status, notes, created_by_user_id)
			VALUES (?, ?, CAST(? AS date), CAST(? AS date),
			        ?, ?, ?, ?, ?, ?, 'draft', ?, ?)
			RETURNING id`,
			tc.GymID(), p.TrainerID,
			p.PeriodStart.Format("2006-01-02"), p.PeriodEnd.Format("2006-01-02"),
			p.SalaryInPaise, p.CommissionInPaise, p.SessionsInPaise,
			p.AdjustmentInPaise, p.AdjustmentReason, p.TotalInPaise,
			p.Notes, tc.UserID())
		if err := row.Scan(&id).Error; err != nil {
			return err
		}

		for _, l := range lines {
			if err := tx.Exec(`
				INSERT INTO trainer_payout_lines
				    (gym_id, payout_id, kind, reference_id, description,
				     amount_in_paise)
				VALUES (?, ?, ?, ?, ?, ?)`,
				tc.GymID(), id, l.Kind, l.ReferenceID, l.Description,
				l.AmountInPaise).Error; err != nil {
				return err
			}
		}
		return nil
	})
	return id, err
}

// MarkPaid records money leaving, and who let it go.
//
// Guarded on status so two people clicking at once cannot pay twice; the
// caller treats a zero row count as exactly that race.
func (r *Repository) MarkPaid(
	ctx context.Context, id int64, mode, reference string,
) (int64, error) {
	tc := database.MustGetTenant(ctx)

	res := r.db.WithContext(ctx).Exec(`
		UPDATE trainer_payouts
		   SET status = 'paid', paid_at = NOW(), paid_by_user_id = ?,
		       payment_mode = NULLIF(?, ''), reference_number = NULLIF(?, ''),
		       updated_at = NOW()
		 WHERE id = ? AND gym_id = ? AND status = 'draft'`,
		tc.UserID(), mode, reference, id, tc.GymID())
	return res.RowsAffected, res.Error
}

func (r *Repository) Cancel(ctx context.Context, id int64) (int64, error) {
	tc := database.MustGetTenant(ctx)

	res := r.db.WithContext(ctx).Exec(`
		UPDATE trainer_payouts
		   SET status = 'cancelled', updated_at = NOW()
		 WHERE id = ? AND gym_id = ? AND status = 'draft'`,
		id, tc.GymID())
	return res.RowsAffected, res.Error
}

func (r *Repository) List(
	ctx context.Context, status string,
) ([]Payout, error) {
	tc := database.MustGetTenant(ctx)

	q := `
		SELECT p.id, p.trainer_id,
		       TRIM(t.first_name || ' ' || COALESCE(t.last_name, '')) AS trainer,
		       p.period_start, p.period_end,
		       p.salary_in_paise, p.commission_in_paise, p.sessions_in_paise,
		       p.adjustment_in_paise, p.adjustment_reason, p.total_in_paise,
		       p.status, p.notes, p.paid_at, p.payment_mode, p.reference_number,
		       u.name AS paid_by, p.created_at
		  FROM trainer_payouts p
		  JOIN trainers t ON t.id = p.trainer_id
		  LEFT JOIN users u ON u.id = p.paid_by_user_id
		 WHERE p.gym_id = ?`
	args := []interface{}{tc.GymID()}
	if status != "" {
		q += ` AND p.status = ?`
		args = append(args, status)
	}
	q += ` ORDER BY p.period_end DESC, trainer ASC`

	var rows []Payout
	err := r.db.WithContext(ctx).Raw(q, args...).Scan(&rows).Error
	return rows, err
}

func (r *Repository) Lines(ctx context.Context, payoutID int64) ([]PayoutLine, error) {
	tc := database.MustGetTenant(ctx)

	var rows []PayoutLine
	err := r.db.WithContext(ctx).Raw(`
		SELECT id, kind, reference_id, description, amount_in_paise
		  FROM trainer_payout_lines
		 WHERE payout_id = ? AND gym_id = ?
		 ORDER BY kind, id`, payoutID, tc.GymID()).Scan(&rows).Error
	return rows, err
}
