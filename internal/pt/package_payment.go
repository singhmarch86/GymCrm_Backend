package pt

import (
	"context"
	"errors"
	"strings"
	"time"

	"gorm.io/gorm"

	"gymcrm/internal/database"
)

// Recording the money for a PT package (FR-21 §3).
//
// Selling personal training is a sale, and a sale that leaves no payment row
// is money the gym can neither count nor chase. Until this existed, creating a
// package wrote one row into pt_packages and nothing else — the live data had
// ₹10,000 of PT with no payment against any of it and no due to collect,
// because no debt had ever been written down.
//
// Deliberately not routed through payments.CollectPayment. That path requires
// a membership plan and creates a renewal as a side effect, so putting PT
// money through it would silently extend memberships nobody bought.

var ErrBadPaidAmount = errors.New("pt: amount paid cannot exceed the package price")

var validModes = map[string]bool{
	"cash": true, "upi": true, "credit_card": true,
	"debit_card": true, "bank_transfer": true,
}

// packagePayment is what the money side of a sale worked out to.
type packagePayment struct {
	PaidInPaise int64
	DueInPaise  int64
	Mode        string
	DueDate     time.Time
	Reference   string
	Notes       string
}

// resolvePayment decides what rows the sale should produce.
//
// The three cases the desk actually sees: paid in full, nothing paid yet, and
// part paid. All three are legitimate, and each produces exactly the rows that
// describe it — never a silent assumption that money arrived.
func resolvePayment(req CreatePackageRequest) (*packagePayment, error) {
	mode := strings.TrimSpace(req.PaymentMode)
	if mode != "" && !validModes[mode] {
		return nil, errors.New("pt: unknown payment mode")
	}

	paid := req.AmountPaidInPaise
	if mode == "" {
		// No mode means no money changed hands, whatever amount was sent.
		paid = 0
	} else if paid <= 0 {
		// A mode with no amount means paid in full, which is the common case
		// at the desk and the one worth making the default.
		paid = req.AmountInPaise
	}
	if paid > req.AmountInPaise {
		return nil, ErrBadPaidAmount
	}

	due := req.AmountInPaise - paid

	dueDate := time.Now()
	if s := strings.TrimSpace(req.DueDate); s != "" {
		d, err := time.Parse("2006-01-02", s)
		if err != nil {
			return nil, errors.New("pt: due date must be YYYY-MM-DD")
		}
		dueDate = d
	}

	return &packagePayment{
		PaidInPaise: paid,
		DueInPaise:  due,
		Mode:        mode,
		DueDate:     dueDate,
		Reference:   strings.TrimSpace(req.ReferenceNumber),
		Notes:       strings.TrimSpace(req.PaymentNotes),
	}, nil
}

// CreatePackageWithPayment writes the package and its money in one
// transaction.
//
// One transaction because a package with no payment row is precisely the state
// this feature exists to prevent. If the payment insert fails, the sale must
// not exist either — a half-written sale is worse than a failed one, because
// nobody knows to retry it.
func (r *Repository) CreatePackageWithPayment(
	ctx context.Context, p *Package, money *packagePayment,
) error {
	tc := database.MustGetTenant(ctx)

	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(p).Error; err != nil {
			return err
		}

		notes := money.Notes
		if notes == "" {
			notes = p.PackageName
		}

		if money.PaidInPaise > 0 {
			if err := tx.Exec(`
				INSERT INTO payments
				    (gym_id, member_id, pt_package_id, amount_in_paise, status,
				     payment_mode, paid_date, reference_number, notes,
				     collected_by_user_id)
				VALUES (?, ?, ?, ?, 'paid', ?, CURRENT_DATE,
				        NULLIF(?, ''), ?, ?)`,
				tc.GymID(), p.MemberID, p.ID, money.PaidInPaise,
				money.Mode, money.Reference, notes, tc.UserID()).Error; err != nil {
				return err
			}
		}

		// Whatever is left is a due, not a rounding error. A part payment that
		// silently forgot its balance is the same leak in a smaller costume.
		if money.DueInPaise > 0 {
			if err := tx.Exec(`
				INSERT INTO payments
				    (gym_id, member_id, pt_package_id, amount_in_paise, status,
				     due_date, notes)
				VALUES (?, ?, ?, ?, 'pending', CAST(? AS date), ?)`,
				tc.GymID(), p.MemberID, p.ID, money.DueInPaise,
				money.DueDate.Format("2006-01-02"), notes).Error; err != nil {
				return err
			}
		}
		return nil
	})
}
