package invoicing

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"gymcrm/internal/database"
)

// Repository owns invoice, line, discount and settings persistence.
//
// CONCURRENCY: issuing an invoice reads-then-writes a per-(gym, FY) counter,
// which races if two staff issue at the same moment. The counter row is locked
// FOR UPDATE inside the same transaction that writes the invoice number, so
// numbering stays gapless and duplicate-free — FR-04 §1.1. Same pattern as
// class booking capacity (internal/classes) and PT session credits
// (internal/pt).
type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository { return &Repository{db: db} }

func (r *Repository) DB() *gorm.DB { return r.db }

// ─── Invoices ─────────────────────────────────────────────────────────────────

func (r *Repository) CreateInvoice(ctx context.Context, inv *Invoice) error {
	return database.ScopedDB(ctx, r.db).Create(inv).Error
}

func (r *Repository) FindInvoice(ctx context.Context, id int64) (*Invoice, error) {
	var inv Invoice
	err := database.ScopedDB(ctx, r.db).Where("id = ?", id).Take(&inv).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &inv, err
}

func (r *Repository) UpdateInvoiceFields(ctx context.Context, id int64, fields map[string]any) error {
	fields["updated_at"] = time.Now()
	return database.ScopedDB(ctx, r.db).Table("invoices").Where("id = ?", id).Updates(fields).Error
}

func (r *Repository) DeleteDraft(ctx context.Context, id int64) error {
	// Items cascade at the DB level.
	return database.ScopedDB(ctx, r.db).
		Where("id = ? AND status = ?", id, StatusDraft).
		Delete(&Invoice{}).Error
}

// invoiceRow carries the display fields joined from members plus the summed
// payments behind the derived payment state.
type invoiceRow struct {
	Invoice
	MemberFirstName string
	MemberLastName  string
	MemberPhone     string
	PaidInPaise     int64
}

const invoiceSelect = `invoices.*,
	m.first_name AS member_first_name,
	m.last_name  AS member_last_name,
	m.phone      AS member_phone,
	COALESCE((
		SELECT SUM(p.amount_in_paise) FROM payments p
		WHERE p.invoice_id = invoices.id AND p.status = 'paid'
	), 0) AS paid_in_paise`

func (r *Repository) ListInvoices(ctx context.Context, memberID *int64, status string) ([]invoiceRow, error) {
	tc := database.MustGetTenant(ctx)
	q := r.db.WithContext(ctx).
		Table("invoices").
		Select(invoiceSelect).
		Joins("JOIN members m ON m.id = invoices.member_id").
		Where("invoices.gym_id = ?", tc.GymID())
	if memberID != nil {
		q = q.Where("invoices.member_id = ?", *memberID)
	}
	if status != "" {
		q = q.Where("invoices.status = ?", status)
	}
	var rows []invoiceRow
	err := q.Order("invoices.created_at DESC").Scan(&rows).Error
	return rows, err
}

func (r *Repository) invoiceRowByID(ctx context.Context, id int64) (*invoiceRow, error) {
	tc := database.MustGetTenant(ctx)
	var row invoiceRow
	err := r.db.WithContext(ctx).
		Table("invoices").
		Select(invoiceSelect).
		Joins("JOIN members m ON m.id = invoices.member_id").
		Where("invoices.id = ? AND invoices.gym_id = ?", id, tc.GymID()).
		Take(&row).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &row, err
}

// ─── Line items ───────────────────────────────────────────────────────────────

func (r *Repository) CreateItem(ctx context.Context, item *InvoiceItem) error {
	return database.ScopedDB(ctx, r.db).Create(item).Error
}

func (r *Repository) ListItems(ctx context.Context, invoiceID int64) ([]InvoiceItem, error) {
	var items []InvoiceItem
	err := database.ScopedDB(ctx, r.db).
		Where("invoice_id = ?", invoiceID).
		Order("id").
		Find(&items).Error
	return items, err
}

func (r *Repository) DeleteItem(ctx context.Context, invoiceID, itemID int64) (int64, error) {
	res := database.ScopedDB(ctx, r.db).
		Where("invoice_id = ? AND id = ?", invoiceID, itemID).
		Delete(&InvoiceItem{})
	return res.RowsAffected, res.Error
}

// ─── Totals ───────────────────────────────────────────────────────────────────

// RecalculateTotals recomputes an invoice's totals from its lines. Called after
// every line or discount change while the invoice is still a draft; never after
// issue, since issued invoices are frozen.
func (r *Repository) RecalculateTotals(ctx context.Context, invoiceID int64) error {
	items, err := r.ListItems(ctx, invoiceID)
	if err != nil {
		return err
	}
	inv, err := r.FindInvoice(ctx, invoiceID)
	if err != nil {
		return err
	}
	if inv == nil {
		return ErrInvoiceNotFound
	}

	var subtotal, tax, total int64
	for _, it := range items {
		gross, _, _, lineTotal := lineAmounts(
			it.UnitPriceInPaise, it.Quantity, it.DiscountInPaise, it.TaxRatePct, inv.PricesIncludeTax,
		)
		subtotal += gross
		tax += it.TaxInPaise
		total += lineTotal
	}

	// The invoice-level discount comes off after the lines are summed. Clamp so
	// a large discount can zero an invoice but never invert it.
	invDiscount := inv.DiscountInPaise
	if invDiscount > total {
		invDiscount = total
	}
	total -= invDiscount

	return r.UpdateInvoiceFields(ctx, invoiceID, map[string]any{
		"subtotal_in_paise": subtotal,
		"tax_in_paise":      tax,
		"total_in_paise":    total,
		"discount_in_paise": invDiscount,
	})
}

// ─── Issuing: the gapless-numbering transaction ───────────────────────────────

// IssueInvoice assigns the next number for the gym's current financial year and
// flips the invoice to issued — atomically.
//
// The sequence row is locked FOR UPDATE, so a second concurrent issue blocks
// until this transaction commits and then reads the incremented value. A
// Postgres SEQUENCE would be wrong here: sequences are non-transactional and
// leave gaps on rollback, and GST numbering must be gapless.
func (r *Repository) IssueInvoice(ctx context.Context, invoiceID int64, invoiceDate time.Time, prefix string, snapshot map[string]any) (string, string, error) {
	tc := database.MustGetTenant(ctx)
	fy := financialYear(invoiceDate)
	var number string

	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// Ensure the counter row exists before locking it. ON CONFLICT DO
		// NOTHING keeps this safe when two transactions race to create it.
		if err := tx.Exec(`
			INSERT INTO invoice_sequences (gym_id, financial_year, last_seq)
			VALUES (?, ?, 0) ON CONFLICT (gym_id, financial_year) DO NOTHING`,
			tc.GymID(), fy).Error; err != nil {
			return err
		}

		var seq InvoiceSequence
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("gym_id = ? AND financial_year = ?", tc.GymID(), fy).
			Take(&seq).Error; err != nil {
			return err
		}

		next := seq.LastSeq + 1
		number = fmt.Sprintf("%s/%s/%04d", prefix, fy, next)

		if err := tx.Table("invoice_sequences").
			Where("gym_id = ? AND financial_year = ?", tc.GymID(), fy).
			Updates(map[string]any{"last_seq": next, "updated_at": time.Now()}).Error; err != nil {
			return err
		}

		fields := map[string]any{
			"invoice_number": number,
			"financial_year": fy,
			"status":         StatusIssued,
			"invoice_date":   invoiceDate,
			"updated_at":     time.Now(),
		}
		for k, v := range snapshot {
			fields[k] = v
		}

		// Guard against a double-issue racing past the service-level check:
		// only a row still in draft may be numbered.
		res := tx.Table("invoices").
			Where("id = ? AND gym_id = ? AND status = ?", invoiceID, tc.GymID(), StatusDraft).
			Updates(fields)
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected == 0 {
			return ErrInvoiceNotDraft
		}
		return nil
	})

	return number, fy, err
}

// ─── Discounts ────────────────────────────────────────────────────────────────

func (r *Repository) CreateDiscount(ctx context.Context, d *Discount) error {
	return database.ScopedDB(ctx, r.db).Create(d).Error
}

func (r *Repository) FindDiscount(ctx context.Context, id int64) (*Discount, error) {
	var d Discount
	err := database.ScopedDB(ctx, r.db).Where("id = ?", id).Take(&d).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &d, err
}

func (r *Repository) FindDiscountByCode(ctx context.Context, code string) (*Discount, error) {
	tc := database.MustGetTenant(ctx)
	var d Discount
	err := r.db.WithContext(ctx).
		Where("gym_id = ? AND LOWER(code) = ?", tc.GymID(), strings.ToLower(strings.TrimSpace(code))).
		Take(&d).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &d, err
}

func (r *Repository) ListDiscounts(ctx context.Context, activeOnly bool) ([]Discount, error) {
	q := database.ScopedDB(ctx, r.db)
	if activeOnly {
		q = q.Where("is_active = ?", true)
	}
	var out []Discount
	err := q.Order("created_at DESC").Find(&out).Error
	return out, err
}

func (r *Repository) UpdateDiscount(ctx context.Context, id int64, fields map[string]any) error {
	fields["updated_at"] = time.Now()
	return database.ScopedDB(ctx, r.db).Table("discounts").Where("id = ?", id).Updates(fields).Error
}

// IncrementDiscountUsage bumps times_used. Called once, at issue time — never
// when a draft merely has a discount attached (FR-04 §4 rule 4).
func (r *Repository) IncrementDiscountUsage(ctx context.Context, id int64) error {
	return database.ScopedDB(ctx, r.db).Table("discounts").Where("id = ?", id).
		UpdateColumn("times_used", gorm.Expr("times_used + 1")).Error
}

// ─── Settings ─────────────────────────────────────────────────────────────────

func (r *Repository) GetSettings(ctx context.Context) (*BillingSettings, error) {
	tc := database.MustGetTenant(ctx)
	var s BillingSettings
	err := r.db.WithContext(ctx).Where("gym_id = ?", tc.GymID()).Take(&s).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &s, err
}

func (r *Repository) UpsertSettings(ctx context.Context, fields map[string]any) error {
	tc := database.MustGetTenant(ctx)
	fields["gym_id"] = tc.GymID()
	fields["updated_at"] = time.Now()
	return r.db.WithContext(ctx).Table("gym_billing_settings").
		Clauses(clause.OnConflict{
			Columns:   []clause.Column{{Name: "gym_id"}},
			DoUpdates: clause.AssignmentColumns(keysOf(fields, "gym_id")),
		}).
		Create(fields).Error
}

func keysOf(m map[string]any, except ...string) []string {
	skip := make(map[string]bool, len(except))
	for _, e := range except {
		skip[e] = true
	}
	out := make([]string, 0, len(m))
	for k := range m {
		if !skip[k] {
			out = append(out, k)
		}
	}
	return out
}

// ─── Cross-module reads ───────────────────────────────────────────────────────

// memberExists guards invoice creation. A plain existence check rather than a
// join to the members module — this package never owns member data.
func (r *Repository) memberExists(ctx context.Context, memberID int64) (bool, error) {
	tc := database.MustGetTenant(ctx)
	var n int64
	err := r.db.WithContext(ctx).Table("members").
		Where("id = ? AND gym_id = ?", memberID, tc.GymID()).
		Count(&n).Error
	return n > 0, err
}

type planSnapshot struct {
	Name         string
	PriceInPaise int64
}

// findPlan reads the catalogue so a line can snapshot the plan's current name
// and price — never trusting a price supplied by the client.
func (r *Repository) findPlan(ctx context.Context, planID int64) (*planSnapshot, error) {
	tc := database.MustGetTenant(ctx)
	var p planSnapshot
	err := r.db.WithContext(ctx).Table("membership_plans").
		Select("name, price_in_paise").
		Where("id = ? AND gym_id = ? AND deleted_at IS NULL", planID, tc.GymID()).
		Take(&p).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &p, err
}
