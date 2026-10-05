package queues

import (
	"context"
	"time"

	"gorm.io/gorm"

	"gymcrm/internal/database"
)

type collectionRow struct {
	PaymentID     int64
	MemberID      int64
	Member        string
	Phone         string
	AmountInPaise int64
	DueDate       *time.Time

	MemberTotalInPaise int64
	MemberInactive     bool

	LastActivityType *string
	LastContactAt    *time.Time
	LastContactBy    *string
	LastContactNote  *string
	LastReached      *bool
	PromisedOn       *time.Time
}

// Collections returns every outstanding due with the last thing anybody did
// about it.
//
// Written off is excluded by the status filter, which is the whole reason
// write-off exists as a status rather than a note: the gym needs a way to
// clear a due it has given up on without pretending the money arrived.
func (r *Repository) Collections(
	ctx context.Context, from, to string,
) ([]collectionRow, error) {
	tc := database.MustGetTenant(ctx)

	memberName := `TRIM(m.first_name || ' ' || COALESCE(m.last_name, ''))`

	// Empty from/to means everything. The filter is written so that a due with
	// no date at all survives it — a missing due date is a data problem, and
	// silently dropping those rows would hide the problem rather than show it.
	window := ``
	if from != "" && to != "" {
		window = `
		   AND (p.due_date IS NULL
		        OR p.due_date BETWEEN CAST(@from AS date) AND CAST(@to AS date))`
	}

	sql := `
		SELECT p.id AS payment_id, p.member_id,
		       ` + memberName + ` AS member,
		       COALESCE(m.phone, '') AS phone,
		       p.amount_in_paise, p.due_date,

		       COALESCE(tot.amount, 0) AS member_total_in_paise,
		       (m.expiry_date IS NOT NULL AND m.expiry_date < CURRENT_DATE)
		           AS member_inactive,

		       act.type       AS last_activity_type,
		       act.created_at AS last_contact_at,
		       u.name         AS last_contact_by,
		       act.note       AS last_contact_note,
		       act.reached    AS last_reached,
		       act.promised_on

		  FROM payments p
		  JOIN members m ON m.id = p.member_id

		  -- Everything this member still owes. LATERAL over the page rather
		  -- than a grouped join across the whole table: the outer query is
		  -- already narrowed to outstanding dues.
		  LEFT JOIN LATERAL (
		      SELECT SUM(o.amount_in_paise) AS amount
		        FROM payments o
		       WHERE o.gym_id = p.gym_id
		         AND o.member_id = p.member_id
		         AND o.status IN ('pending', 'overdue')
		  ) tot ON true

		  -- The newest thing anybody did about this due, whatever kind it was.
		  -- One row, not a history: the queue needs to know the current state,
		  -- and the full timeline belongs on the member, not in a worklist.
		  LEFT JOIN LATERAL (
		      SELECT a.type, a.created_at, a.note, a.reached, a.promised_on,
		             a.user_id
		        FROM payment_activities a
		       WHERE a.payment_id = p.id
		       ORDER BY a.created_at DESC
		       LIMIT 1
		  ) act ON true
		  LEFT JOIN users u ON u.id = act.user_id

		 WHERE p.gym_id = @gym
		   AND p.status IN ('pending', 'overdue')
		   AND m.deleted_at IS NULL` + window + `

		 -- Oldest first within the groups the service builds. A due with no
		 -- date sorts last rather than first: it is a data problem, not the
		 -- most urgent debt in the gym.
		 ORDER BY p.due_date ASC NULLS LAST, p.amount_in_paise DESC`

	var rows []collectionRow
	err := r.db.WithContext(ctx).Raw(sql, map[string]interface{}{
		"gym":  tc.GymID(),
		"from": from,
		"to":   to,
	}).Scan(&rows).Error
	return rows, err
}

// OutsideWindow counts the dues a window excludes.
//
// Reported, never silently dropped. Filtering collections by due date hides
// the oldest debt, which is the worst debt — the reader has to be told.
func (r *Repository) OutsideWindow(
	ctx context.Context, from, to string,
) (int, int64, error) {
	tc := database.MustGetTenant(ctx)

	var row struct {
		N      int
		Amount int64
	}
	err := r.db.WithContext(ctx).Raw(`
		SELECT COUNT(*) AS n, COALESCE(SUM(p.amount_in_paise), 0) AS amount
		  FROM payments p
		  JOIN members m ON m.id = p.member_id
		 WHERE p.gym_id = @gym
		   AND p.status IN ('pending', 'overdue')
		   AND m.deleted_at IS NULL
		   AND p.due_date IS NOT NULL
		   AND p.due_date NOT BETWEEN CAST(@from AS date) AND CAST(@to AS date)`,
		map[string]interface{}{
			"gym":  tc.GymID(),
			"from": from,
			"to":   to,
		}).Scan(&row).Error
	return row.N, row.Amount, err
}

// PaymentActivity is one insert into the collections ledger.
type PaymentActivity struct {
	ID         int64      `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID      int64      `gorm:"not null" json:"gym_id"`
	PaymentID  int64      `gorm:"not null" json:"payment_id"`
	Type       string     `gorm:"not null" json:"type"`
	Channel    *string    `json:"channel,omitempty"`
	Reached    *bool      `json:"reached,omitempty"`
	PromisedOn *time.Time `json:"promised_on,omitempty"`
	Note       *string    `json:"note,omitempty"`
	UserID     int64      `gorm:"not null" json:"user_id"`
	CreatedAt  time.Time  `gorm:"autoCreateTime" json:"created_at"`
}

func (PaymentActivity) TableName() string { return "payment_activities" }

// PaymentBelongsToGym guards every write. Without it a payment id from another
// gym would be accepted, because the activity insert carries its own gym_id
// and would look perfectly consistent.
func (r *Repository) PaymentBelongsToGym(ctx context.Context, paymentID int64) (bool, error) {
	tc := database.MustGetTenant(ctx)

	var n int64
	err := r.db.WithContext(ctx).
		Table("payments").
		Where("id = ? AND gym_id = ?", paymentID, tc.GymID()).
		Count(&n).Error
	return n > 0, err
}

func (r *Repository) AddActivity(ctx context.Context, a *PaymentActivity) error {
	tc := database.MustGetTenant(ctx)
	a.GymID = tc.GymID()
	a.UserID = tc.UserID()
	return r.db.WithContext(ctx).Create(a).Error
}

// Settle marks an existing outstanding due as paid.
//
// Distinct from payments.Collect, which creates a new payment row. The queue
// needs to settle the due that is already there — collecting through Collect
// would leave the original pending and add a second row for the same money,
// so the queue could never be driven to zero by actually being paid.
//
// The status guard is in the WHERE clause rather than a read-then-write, so
// two people collecting the same due at the counter cannot both succeed.
func (r *Repository) Settle(
	ctx context.Context, paymentID int64, mode string, reference string,
) error {
	tc := database.MustGetTenant(ctx)

	fields := map[string]interface{}{
		"status":               "paid",
		"payment_mode":         mode,
		"paid_date":            time.Now().In(IST).Format("2006-01-02"),
		"collected_by_user_id": tc.UserID(),
		"updated_at":           time.Now(),
	}
	if reference != "" {
		fields["reference_number"] = reference
	}

	res := r.db.WithContext(ctx).
		Table("payments").
		Where("id = ? AND gym_id = ? AND status IN ('pending','overdue')",
			paymentID, tc.GymID()).
		Updates(fields)
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected == 0 {
		return ErrNotOutstanding
	}
	return nil
}

// WriteOff records the reason and takes the due out of the queue in one
// transaction. Doing them separately could leave money written off with no
// stated reason, which is the one thing an auditor will ask about.
func (r *Repository) WriteOff(ctx context.Context, paymentID int64, reason string) error {
	tc := database.MustGetTenant(ctx)

	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		res := tx.Table("payments").
			Where("id = ? AND gym_id = ? AND status IN ('pending','overdue')",
				paymentID, tc.GymID()).
			Updates(map[string]interface{}{
				"status":     "written_off",
				"updated_at": time.Now(),
			})
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected == 0 {
			return ErrNotOutstanding
		}

		return tx.Create(&PaymentActivity{
			GymID:     tc.GymID(),
			PaymentID: paymentID,
			Type:      ActivityWriteOff,
			Note:      &reason,
			UserID:    tc.UserID(),
		}).Error
	})
}

// RaiseDue records that a member owes money.
//
// Distinct from payments.CollectPayment, which only ever writes a *paid* row —
// it requires a payment mode and stamps paid_date. Until this existed there was
// no way to say "this member owes us" at all, so the collections queue could
// only ever show dues that some other process happened to create. A gym that
// does not raise the due cannot chase it.
//
// status is 'pending' with no paid_date and no payment_mode, which the
// chk_payments_paid_consistency constraint requires of anything not paid.
func (r *Repository) RaiseDue(
	ctx context.Context, memberID int64, planID *int64,
	amountInPaise int64, dueDate time.Time, notes string,
) (int64, error) {
	tc := database.MustGetTenant(ctx)

	// collected_by_user_id is deliberately left null. Nobody has collected
	// anything yet — filling it with whoever raised the due would credit them
	// with money that has not arrived.
	var id int64
	err := r.db.WithContext(ctx).Raw(`
		INSERT INTO payments (gym_id, member_id, plan_id, amount_in_paise,
		                      status, due_date, notes, created_at, updated_at)
		VALUES (@gym_id, @member_id, @plan_id, @amount_in_paise,
		        'pending', CAST(@due_date AS date), @notes, NOW(), NOW())
		RETURNING id`,
		map[string]interface{}{
			"gym_id":          tc.GymID(),
			"member_id":       memberID,
			"plan_id":         planID,
			"amount_in_paise": amountInPaise,
			"due_date":        dueDate.Format("2006-01-02"),
			"notes":           nullIfEmpty(notes),
		}).Scan(&id).Error
	return id, err
}

// MemberBelongsToGym guards the write, for the same reason payments do: an id
// from another gym would otherwise be accepted and the row would look
// perfectly consistent.
func (r *Repository) MemberBelongsToGym(ctx context.Context, memberID int64) (bool, error) {
	tc := database.MustGetTenant(ctx)

	var n int64
	err := r.db.WithContext(ctx).
		Table("members").
		Where("id = ? AND gym_id = ? AND deleted_at IS NULL", memberID, tc.GymID()).
		Count(&n).Error
	return n > 0, err
}

func nullIfEmpty(s string) interface{} {
	if s == "" {
		return nil
	}
	return s
}
