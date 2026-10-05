package stocktransfer

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

var (
	ErrProductNotFound = errors.New("product not found in this branch")
	ErrNotEnoughStock  = errors.New("not enough stock to send")
	ErrNoAccess        = errors.New("no access to that branch")
	ErrSameBranch      = errors.New("source and destination are the same branch")
	ErrDifferentOrg    = errors.New("that branch is not in your organization")
	ErrBadQuantity     = errors.New("quantity must be between 1 and 9999")
)

type Repository struct{ db *gorm.DB }

func NewRepository(db *gorm.DB) *Repository { return &Repository{db: db} }

// ─── Visibility ───────────────────────────────────────────────────────────────

// VisibleBranches lists the branches this user may act in, newest access last.
//
// Access is the boundary, not the organization: an owner of two of a chain's
// five branches sees two. A view that showed all five would be showing them
// stock they cannot move and cannot count.
func (r *Repository) VisibleBranches(ctx context.Context, userID int64) ([]BranchRef, error) {
	var rows []struct {
		GymID      int64
		Name       string
		BranchName *string
	}
	err := r.db.WithContext(ctx).
		Table("user_gym_access uga").
		Select("g.id AS gym_id, g.name, g.branch_name").
		Joins("JOIN gyms g ON g.id = uga.gym_id").
		Where("uga.user_id = ? AND g.status = 'active'", userID).
		Order("g.id").
		Scan(&rows).Error
	if err != nil {
		return nil, err
	}

	out := make([]BranchRef, 0, len(rows))
	for _, row := range rows {
		out = append(out, BranchRef{GymID: row.GymID, Name: label(row.Name, row.BranchName)})
	}
	return out, nil
}

// BranchLabel names a single gym, for the common case of a gym that has no
// access rows because it is not a chain and never needed any.
func (r *Repository) BranchLabel(ctx context.Context, gymID int64) (string, error) {
	var row struct {
		Name       string
		BranchName *string
	}
	err := r.db.WithContext(ctx).Table("gyms").
		Select("name, branch_name").Where("id = ?", gymID).
		Limit(1).Scan(&row).Error
	return label(row.Name, row.BranchName), err
}

func label(name string, branch *string) string {
	if branch != nil && strings.TrimSpace(*branch) != "" {
		return *branch
	}
	return name
}

// ─── The chain view ───────────────────────────────────────────────────────────

type stockRow struct {
	GymID        int64
	Branch       string
	BranchName   *string
	ProductID    int64
	SKU          *string
	Name         string
	Category     *string
	StockQty     int
	ReorderLevel int
	CostInPaise  int64
	PriceInPaise int64
	SoldRecently int
}

// StockAcross returns every active product at the given branches, with how
// many units each has sold over the trailing window.
//
// The sold figure is what separates "a lot of stock" from "too much stock".
// Twelve tubs of protein is a healthy shelf at a branch that sells four a
// week and a dead asset at one that sells none.
func (r *Repository) StockAcross(ctx context.Context, gymIDs []int64, windowDays int) ([]stockRow, error) {
	if len(gymIDs) == 0 {
		return nil, nil
	}
	var rows []stockRow
	err := r.db.WithContext(ctx).Raw(`
		SELECT p.gym_id,
		       g.name         AS branch,
		       g.branch_name  AS branch_name,
		       p.id           AS product_id,
		       p.sku, p.name, p.category,
		       p.stock_qty, p.reorder_level,
		       p.cost_in_paise, p.price_in_paise,
		       COALESCE(s.sold, 0) AS sold_recently
		FROM products p
		JOIN gyms g ON g.id = p.gym_id
		LEFT JOIN (
		    SELECT si.product_id, SUM(si.quantity) AS sold
		    FROM sale_items si
		    JOIN sales sa ON sa.id = si.sale_id
		    WHERE sa.created_at >= now() - make_interval(days => ?)
		      AND sa.is_refund = false
		    GROUP BY si.product_id
		) s ON s.product_id = p.id
		WHERE p.gym_id IN ?
		  AND p.is_active = true
		  AND p.deleted_at IS NULL
		ORDER BY p.name, p.gym_id`,
		windowDays, gymIDs).Scan(&rows).Error
	return rows, err
}

// ─── Transfers ────────────────────────────────────────────────────────────────

// ResolveDestination finds the destination branch's row for the same item,
// creating it if the branch does not carry it yet.
//
// Matching is by SKU when the source has one and by name otherwise. Created
// rows copy price, cost, tax and reorder level from the source, because the
// alternative is a product that arrives priced at zero and gets sold that way
// by a front desk that had no reason to check.
func (r *Repository) ResolveDestination(ctx context.Context, tx *gorm.DB, src *product, toGymID int64) (int64, error) {
	q := tx.Table("products").
		Select("id").
		Where("gym_id = ? AND deleted_at IS NULL", toGymID)

	if src.SKU != nil && strings.TrimSpace(*src.SKU) != "" {
		q = q.Where("lower(sku) = lower(?)", strings.TrimSpace(*src.SKU))
	} else {
		q = q.Where("sku IS NULL AND lower(name) = lower(?)", src.Name)
	}

	var id int64
	err := q.Limit(1).Scan(&id).Error
	if err != nil {
		return 0, err
	}
	if id != 0 {
		return id, nil
	}

	// Not carried here yet. Create it dormant-but-active at zero stock; the
	// transfer_in movement immediately below is what puts units on the shelf,
	// so the level still arrives through a movement rather than a direct write.
	var newID int64
	err = tx.Raw(`
		INSERT INTO products
		  (gym_id, sku, name, category, description, price_in_paise, cost_in_paise,
		   tax_rate_pct, stock_qty, reorder_level, is_active, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, true, now(), now())
		RETURNING id`,
		toGymID, src.SKU, src.Name, src.Category, src.Description,
		src.PriceInPaise, src.CostInPaise, src.TaxRatePct, src.ReorderLevel,
	).Scan(&newID).Error
	if err != nil {
		return 0, fmt.Errorf("create destination product: %w", err)
	}
	return newID, nil
}

// product is the subset of pos.Product this module reads. Declared locally so
// inventory transfer does not import the till.
type product struct {
	ID           int64
	GymID        int64
	SKU          *string
	Name         string
	Category     *string
	Description  *string
	PriceInPaise int64
	CostInPaise  int64
	TaxRatePct   float64
	StockQty     int
	ReorderLevel int
}

func (product) TableName() string { return "products" }

// Move performs the transfer: both levels, both movements, one header, one
// transaction.
//
// Rows are locked in gym-id order rather than the order the caller asked for.
// Two desks sending to each other at the same moment would otherwise each hold
// the row the other is waiting for.
func (r *Repository) Move(ctx context.Context, productID, toGymID int64, qty int, reason string) (*Transfer, error) {
	tc := database.MustGetTenant(ctx)
	fromGymID := tc.GymID()

	var out Transfer
	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		src, err := lockProduct(tx, productID, fromGymID)
		if err != nil {
			return err
		}
		if src == nil {
			return ErrProductNotFound
		}
		if src.StockQty < qty {
			return ErrNotEnoughStock
		}

		dstID, err := r.ResolveDestination(ctx, tx, src, toGymID)
		if err != nil {
			return err
		}
		dst, err := lockProduct(tx, dstID, toGymID)
		if err != nil {
			return err
		}
		if dst == nil {
			return ErrProductNotFound
		}

		unitCost := src.CostInPaise
		header := Transfer{
			FromGymID: fromGymID, ToGymID: toGymID,
			FromProductID: src.ID, ToProductID: dst.ID,
			Quantity:        qty,
			UnitCostInPaise: unitCost,
			ValueInPaise:    unitCost * int64(qty),
			Reason:          optional(reason),
			CreatedByUserID: tc.UserID(),
		}
		if err := tx.Create(&header).Error; err != nil {
			return err
		}

		srcAfter := src.StockQty - qty
		dstAfter := dst.StockQty + qty

		if err := setLevel(tx, src.ID, srcAfter); err != nil {
			return err
		}
		if err := setLevel(tx, dst.ID, dstAfter); err != nil {
			return err
		}

		if err := writeMovement(tx, fromGymID, src.ID, MovementTransferOut,
			-qty, srcAfter, header.ID, tc.UserID(), reason); err != nil {
			return err
		}
		if err := writeMovement(tx, toGymID, dst.ID, MovementTransferIn,
			qty, dstAfter, header.ID, tc.UserID(), reason); err != nil {
			return err
		}

		out = header
		return nil
	})
	if err != nil {
		return nil, err
	}
	return &out, nil
}

func lockProduct(tx *gorm.DB, id, gymID int64) (*product, error) {
	var p product
	err := tx.Table("products").
		Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("id = ? AND gym_id = ? AND deleted_at IS NULL", id, gymID).
		Take(&p).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &p, err
}

func setLevel(tx *gorm.DB, productID int64, qty int) error {
	return tx.Table("products").Where("id = ?", productID).
		Updates(map[string]any{"stock_qty": qty, "updated_at": time.Now()}).Error
}

func writeMovement(tx *gorm.DB, gymID, productID int64, kind string,
	qty, after int, transferID, byUserID int64, reason string) error {
	return tx.Exec(`
		INSERT INTO stock_movements
		  (gym_id, product_id, movement_type, quantity, qty_after, reason,
		   transfer_id, created_by_user_id, created_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, now())`,
		gymID, productID, kind, qty, after, optional(reason), transferID, byUserID).Error
}

// ─── Ledger ───────────────────────────────────────────────────────────────────

// History lists transfers touching this branch in either direction, newest
// first. Both directions in one list on purpose: "what moved through here" is
// the question a manager actually asks, and splitting it into sent and
// received makes them read two screens to answer it.
func (r *Repository) History(ctx context.Context, gymID int64, limit int) ([]TransferRow, error) {
	var rows []struct {
		ID        int64
		Product   string
		Quantity  int
		FromGymID int64
		ToGymID   int64
		FromName  string
		FromLabel *string
		ToName    string
		ToLabel   *string
		Value     int64
		Reason    *string
		By        string
		At        time.Time
	}
	err := r.db.WithContext(ctx).Raw(`
		SELECT t.id, p.name AS product, t.quantity,
		       t.from_gym_id, t.to_gym_id,
		       fg.name AS from_name, fg.branch_name AS from_label,
		       tg.name AS to_name,   tg.branch_name AS to_label,
		       t.value_in_paise AS value, t.reason,
		       COALESCE(u.name, 'Unknown') AS by,
		       t.created_at AS at
		FROM stock_transfers t
		JOIN products p ON p.id = t.from_product_id
		JOIN gyms fg ON fg.id = t.from_gym_id
		JOIN gyms tg ON tg.id = t.to_gym_id
		LEFT JOIN users u ON u.id = t.created_by_user_id
		WHERE t.from_gym_id = ? OR t.to_gym_id = ?
		ORDER BY t.created_at DESC
		LIMIT ?`, gymID, gymID, limit).Scan(&rows).Error
	if err != nil {
		return nil, err
	}

	out := make([]TransferRow, 0, len(rows))
	for _, row := range rows {
		dir := "in"
		if row.FromGymID == gymID {
			dir = "out"
		}
		out = append(out, TransferRow{
			ID: row.ID, Product: row.Product, Quantity: row.Quantity,
			FromGymID: row.FromGymID, ToGymID: row.ToGymID,
			FromName:  label(row.FromName, row.FromLabel),
			ToName:    label(row.ToName, row.ToLabel),
			Direction: dir, Value: row.Value, Reason: row.Reason,
			By: row.By, At: row.At,
		})
	}
	return out, nil
}

func optional(s string) *string {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	return &s
}
