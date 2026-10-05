package queues

import (
	"context"
	"time"

	"gymcrm/internal/database"
)

type invoiceableDue struct {
	PaymentID     int64
	MemberID      int64
	Member        string
	AmountInPaise int64
	DueDate       *time.Time
	PlanID        *int64
	PlanName      *string
	Notes         *string
}

// InvoiceableDues returns the requested dues that can actually be invoiced.
//
// Filters rather than validates one at a time: anything missing from the
// result was either settled, written off, already on an invoice, or belongs to
// another gym. The caller diffs against what it asked for and reports each
// omission, so nothing disappears quietly.
func (r *Repository) InvoiceableDues(
	ctx context.Context, ids []int64,
) ([]invoiceableDue, error) {
	tc := database.MustGetTenant(ctx)

	var rows []invoiceableDue
	err := r.db.WithContext(ctx).Raw(`
		SELECT p.id AS payment_id,
		       p.member_id,
		       TRIM(m.first_name || ' ' || COALESCE(m.last_name, '')) AS member,
		       p.amount_in_paise,
		       p.due_date,
		       p.plan_id,
		       pl.name AS plan_name,
		       p.notes
		  FROM payments p
		  JOIN members m ON m.id = p.member_id AND m.deleted_at IS NULL
		  LEFT JOIN membership_plans pl ON pl.id = p.plan_id
		 WHERE p.gym_id = ?
		   AND p.id IN ?
		   AND p.status IN ('pending', 'overdue')
		   AND p.invoice_id IS NULL
		 ORDER BY p.member_id, p.due_date NULLS LAST, p.id`,
		tc.GymID(), ids).Scan(&rows).Error
	return rows, err
}

// DueStates reports the status and invoice link of every requested due, so a
// skip can say which of the several possible reasons applied.
type dueState struct {
	PaymentID int64
	Status    string
	InvoiceID *int64
}

func (r *Repository) DueStates(
	ctx context.Context, ids []int64,
) (map[int64]dueState, error) {
	tc := database.MustGetTenant(ctx)

	var rows []dueState
	err := r.db.WithContext(ctx).Raw(`
		SELECT id AS payment_id, status, invoice_id
		  FROM payments
		 WHERE gym_id = ? AND id IN ?`, tc.GymID(), ids).Scan(&rows).Error
	if err != nil {
		return nil, err
	}

	out := make(map[int64]dueState, len(rows))
	for _, row := range rows {
		out[row.PaymentID] = row
	}
	return out, nil
}

// LinkDuesToInvoice points the dues at the document that now covers them.
//
// The `invoice_id IS NULL` guard is not decoration: it is what stops two
// people invoicing the same due from two screens a second apart. The caller
// checks the affected count and treats a short write as the race it is.
func (r *Repository) LinkDuesToInvoice(
	ctx context.Context, invoiceID int64, paymentIDs []int64,
) (int64, error) {
	tc := database.MustGetTenant(ctx)

	res := r.db.WithContext(ctx).Exec(`
		UPDATE payments
		   SET invoice_id = ?, updated_at = NOW()
		 WHERE gym_id = ? AND id IN ? AND invoice_id IS NULL
		   AND status IN ('pending', 'overdue')`,
		invoiceID, tc.GymID(), paymentIDs)
	return res.RowsAffected, res.Error
}
