package pos

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"gymcrm/internal/database"
	"gymcrm/internal/wallet"
)

// Repository owns products, stock movements and sales.
//
// CONCURRENCY: recording a sale reads a product's stock, checks it, then writes
// a lower figure — a check-then-act that races. Two staff selling the last tub
// of protein at the same instant would both succeed and leave stock at -1 with
// no explanation. Each product row is therefore locked FOR UPDATE inside the
// same transaction that writes the sale, its items and its stock movements —
// the same pattern as class capacity (internal/classes) and PT credits
// (internal/pt).
type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository { return &Repository{db: db} }

// ─── Products ─────────────────────────────────────────────────────────────────

func (r *Repository) CreateProduct(ctx context.Context, p *Product) error {
	return database.ScopedDB(ctx, r.db).Create(p).Error
}

func (r *Repository) FindProduct(ctx context.Context, id int64) (*Product, error) {
	var p Product
	err := database.ScopedDB(ctx, r.db).
		Where("id = ? AND deleted_at IS NULL", id).Take(&p).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &p, err
}

func (r *Repository) ListProducts(ctx context.Context, search string, activeOnly, lowStockOnly bool) ([]Product, error) {
	q := database.ScopedDB(ctx, r.db).Where("deleted_at IS NULL")
	if activeOnly {
		q = q.Where("is_active = ?", true)
	}
	if lowStockOnly {
		q = q.Where("stock_qty <= reorder_level")
	}
	if s := strings.TrimSpace(search); s != "" {
		like := "%" + strings.ToLower(s) + "%"
		q = q.Where("LOWER(name) LIKE ? OR LOWER(COALESCE(sku,'')) LIKE ? OR LOWER(COALESCE(category,'')) LIKE ?",
			like, like, like)
	}
	var out []Product
	err := q.Order("name").Find(&out).Error
	return out, err
}

func (r *Repository) UpdateProduct(ctx context.Context, id int64, fields map[string]any) error {
	fields["updated_at"] = time.Now()
	// stock_qty is deliberately not settable here: it moves only through
	// recorded movements (FR-07 §1).
	delete(fields, "stock_qty")
	return database.ScopedDB(ctx, r.db).Table("products").Where("id = ?", id).Updates(fields).Error
}

func (r *Repository) SoftDeleteProduct(ctx context.Context, id int64) error {
	return database.ScopedDB(ctx, r.db).Table("products").Where("id = ?", id).
		Updates(map[string]any{"deleted_at": time.Now(), "is_active": false}).Error
}

// ─── Stock ────────────────────────────────────────────────────────────────────

// AdjustStock records a movement and moves the product's level by the same
// signed amount, atomically. Used for purchases, corrections, wastage and
// returns — everything except sales, which move stock as part of the sale
// transaction.
func (r *Repository) AdjustStock(ctx context.Context, productID int64, qty int, movementType, reason string) (*Product, error) {
	tc := database.MustGetTenant(ctx)
	var updated Product

	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		p, err := r.lockProduct(ctx, tx, productID)
		if err != nil {
			return err
		}
		if p == nil {
			return ErrProductNotFound
		}

		after := p.StockQty + qty
		if err := tx.Table("products").Where("id = ?", productID).
			Updates(map[string]any{"stock_qty": after, "updated_at": time.Now()}).Error; err != nil {
			return err
		}
		if err := tx.Create(&StockMovement{
			GymID: tc.GymID(), ProductID: productID, MovementType: movementType,
			Quantity: qty, QtyAfter: after, Reason: optional(reason),
			CreatedByUserID: tc.UserID(),
		}).Error; err != nil {
			return err
		}
		p.StockQty = after
		updated = *p
		return nil
	})
	if err != nil {
		return nil, err
	}
	return &updated, nil
}

func (r *Repository) lockProduct(ctx context.Context, tx *gorm.DB, id int64) (*Product, error) {
	tc := database.MustGetTenant(ctx)
	var p Product
	err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("id = ? AND gym_id = ? AND deleted_at IS NULL", id, tc.GymID()).
		Take(&p).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &p, err
}

func (r *Repository) ListMovements(ctx context.Context, productID int64, limit int) ([]StockMovement, error) {
	q := database.ScopedDB(ctx, r.db).Where("product_id = ?", productID).Order("created_at DESC")
	if limit > 0 {
		q = q.Limit(limit)
	}
	var out []StockMovement
	err := q.Find(&out).Error
	return out, err
}

// ─── Sales ────────────────────────────────────────────────────────────────────

// lineInput is one requested line, already priced by the service.
type lineInput struct {
	ProductID int64
	Quantity  int
}

// RecordSale writes the sale, its items, and one stock movement per line — all
// in a single transaction with every product row locked.
//
// allowNegative reflects the gym's setting: blocking a sale the gym physically
// made is worse than a negative figure, because the money then goes unrecorded
// entirely (FR-07 §1.1).
func (r *Repository) RecordSale(
	ctx context.Context,
	sale *Sale,
	lines []lineInput,
	allowNegative bool,
) (*Sale, []SaleItem, error) {
	tc := database.MustGetTenant(ctx)
	var items []SaleItem

	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// Price and validate every line first, with all rows locked, so the
		// sale either happens completely or not at all.
		var subtotal, tax, total int64
		staged := make([]SaleItem, 0, len(lines))

		for _, l := range lines {
			p, err := r.lockProduct(ctx, tx, l.ProductID)
			if err != nil {
				return err
			}
			if p == nil {
				return ErrProductNotFound
			}
			// A refund carries negative quantities, which add stock back rather
			// than consuming it, so the availability check only applies to sales.
			if l.Quantity > 0 && !allowNegative && p.StockQty < l.Quantity {
				return fmt.Errorf("%w: %s has %d in stock, tried to sell %d",
					ErrInsufficientStock, p.Name, p.StockQty, l.Quantity)
			}

			gross := p.PriceInPaise * int64(l.Quantity)
			lineTax := roundHalfUp(float64(gross) * p.TaxRatePct / 100)

			staged = append(staged, SaleItem{
				GymID: tc.GymID(), ProductID: p.ID, ProductName: p.Name,
				UnitPriceInPaise: p.PriceInPaise, CostInPaise: p.CostInPaise,
				TaxRatePct: p.TaxRatePct, Quantity: l.Quantity,
				LineTotalInPaise: gross,
			})
			subtotal += gross
			tax += lineTax
			total += gross
		}

		// Clamp the discount to the sale value — but only for actual sales. A
		// refund's total is negative, and clamping against it would assign the
		// whole negative total as a "discount" and cancel the refund to zero,
		// silently overstating revenue.
		if total > 0 && sale.DiscountInPaise > total {
			sale.DiscountInPaise = total
		}
		if total <= 0 {
			sale.DiscountInPaise = 0
		}
		sale.SubtotalInPaise = subtotal
		sale.TaxInPaise = tax
		sale.TotalInPaise = total - sale.DiscountInPaise
		sale.GymID = tc.GymID()
		sale.CreatedByUserID = tc.UserID()

		if err := tx.Create(sale).Error; err != nil {
			return err
		}

		for i := range staged {
			staged[i].SaleID = sale.ID
			if err := tx.Create(&staged[i]).Error; err != nil {
				return err
			}

			p, err := r.lockProduct(ctx, tx, staged[i].ProductID)
			if err != nil {
				return err
			}
			// Selling removes stock, so the movement is the negation of the
			// quantity sold; a refund's negative quantity therefore adds back.
			delta := -staged[i].Quantity
			after := p.StockQty + delta

			if err := tx.Table("products").Where("id = ?", p.ID).
				Updates(map[string]any{"stock_qty": after, "updated_at": time.Now()}).Error; err != nil {
				return err
			}

			movementType := MovementSale
			if sale.IsRefund {
				movementType = MovementReturn
			}
			saleID := sale.ID
			if err := tx.Create(&StockMovement{
				GymID: tc.GymID(), ProductID: p.ID, MovementType: movementType,
				Quantity: delta, QtyAfter: after, SaleID: &saleID,
				CreatedByUserID: tc.UserID(),
			}).Error; err != nil {
				return err
			}
		}

		// Paying from stored credit happens INSIDE this transaction, so the
		// sale, the stock movements and the wallet debit are one atomic unit.
		// If the balance is short, everything above rolls back — no sale, no
		// stock change, no half-charged member (FR-07 §2, FR-08).
		if sale.PaymentMode == PaymentModeAccount && !sale.IsRefund {
			if sale.MemberID == nil {
				return ErrWalletNeedsMember
			}
			saleID := sale.ID
			if _, err := wallet.ApplyTx(ctx, tx, *sale.MemberID, -sale.TotalInPaise,
				wallet.TypeSpend, "Counter sale", false, &saleID); err != nil {
				return err
			}
		}
		// A refund paid to the wallet puts the credit back the same way.
		if sale.PaymentMode == PaymentModeAccount && sale.IsRefund && sale.MemberID != nil {
			saleID := sale.ID
			if _, err := wallet.ApplyTx(ctx, tx, *sale.MemberID, -sale.TotalInPaise,
				wallet.TypeRefund, "Refund to wallet", true, &saleID); err != nil {
				return err
			}
		}

		items = staged
		return nil
	})

	if err != nil {
		return nil, nil, err
	}
	return sale, items, nil
}

func (r *Repository) FindSale(ctx context.Context, id int64) (*Sale, error) {
	var s Sale
	err := database.ScopedDB(ctx, r.db).Where("id = ?", id).Take(&s).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &s, err
}

func (r *Repository) ListSaleItems(ctx context.Context, saleID int64) ([]SaleItem, error) {
	var out []SaleItem
	err := database.ScopedDB(ctx, r.db).Where("sale_id = ?", saleID).Order("id").Find(&out).Error
	return out, err
}

type saleRow struct {
	Sale
	MemberName *string
}

func (r *Repository) ListSales(ctx context.Context, from, to time.Time, memberID *int64) ([]saleRow, error) {
	tc := database.MustGetTenant(ctx)
	q := r.db.WithContext(ctx).
		Table("sales").
		Select("sales.*, (m.first_name || ' ' || m.last_name) AS member_name").
		Joins("LEFT JOIN members m ON m.id = sales.member_id").
		Where("sales.gym_id = ? AND sales.created_at BETWEEN ? AND ?", tc.GymID(), from, to)
	if memberID != nil {
		q = q.Where("sales.member_id = ?", *memberID)
	}
	var rows []saleRow
	err := q.Order("sales.created_at DESC").Scan(&rows).Error
	return rows, err
}

// ─── Reporting ────────────────────────────────────────────────────────────────

type SalesSummary struct {
	SaleCount         int64 `json:"sale_count"`
	UnitsSold         int64 `json:"units_sold"`
	RevenueInPaise    int64 `json:"revenue_in_paise"`
	CostInPaise       int64 `json:"cost_in_paise"`
	StockValueInPaise int64 `json:"stock_value_in_paise"`
	LowStockCount     int64 `json:"low_stock_count"`
}

func (r *Repository) Summary(ctx context.Context, from, to time.Time) (*SalesSummary, error) {
	tc := database.MustGetTenant(ctx)
	var s SalesSummary

	err := r.db.WithContext(ctx).Raw(`
		SELECT
		  COALESCE((SELECT count(*) FROM sales
		            WHERE gym_id = ? AND created_at BETWEEN ? AND ?), 0) AS sale_count,
		  COALESCE((SELECT sum(si.quantity) FROM sale_items si
		            JOIN sales s ON s.id = si.sale_id
		            WHERE s.gym_id = ? AND s.created_at BETWEEN ? AND ?), 0) AS units_sold,
		  COALESCE((SELECT sum(total_in_paise) FROM sales
		            WHERE gym_id = ? AND created_at BETWEEN ? AND ?), 0) AS revenue_in_paise,
		  COALESCE((SELECT sum(si.cost_in_paise * si.quantity) FROM sale_items si
		            JOIN sales s ON s.id = si.sale_id
		            WHERE s.gym_id = ? AND s.created_at BETWEEN ? AND ?), 0) AS cost_in_paise,
		  COALESCE((SELECT sum(stock_qty * cost_in_paise) FROM products
		            WHERE gym_id = ? AND deleted_at IS NULL), 0) AS stock_value_in_paise,
		  COALESCE((SELECT count(*) FROM products
		            WHERE gym_id = ? AND deleted_at IS NULL AND is_active
		              AND stock_qty <= reorder_level), 0) AS low_stock_count`,
		tc.GymID(), from, to,
		tc.GymID(), from, to,
		tc.GymID(), from, to,
		tc.GymID(), from, to,
		tc.GymID(), tc.GymID(),
	).Scan(&s).Error
	return &s, err
}

// allowNegativeStock reads the gym's retail setting. A gym with no billing
// settings row has never opted in, so the safe default applies.
func (r *Repository) allowNegativeStock(ctx context.Context) (bool, error) {
	tc := database.MustGetTenant(ctx)
	var allow *bool
	err := r.db.WithContext(ctx).Table("gym_billing_settings").
		Select("allow_negative_stock").Where("gym_id = ?", tc.GymID()).
		Limit(1).Scan(&allow).Error
	if err != nil || allow == nil {
		return false, err
	}
	return *allow, nil
}

func optional(s string) *string {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	return &s
}
