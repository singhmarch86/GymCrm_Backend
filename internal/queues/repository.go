package queues

import (
	"context"
	"time"

	"gorm.io/gorm"

	"gymcrm/internal/database"
)

type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository {
	return &Repository{db: db}
}

// IST is the gym's day boundary. Fixed offset rather than a tzdata lookup so
// the binary keeps working in a scratch container with no zoneinfo — the same
// choice staffwork and the rhythm detector make.
var IST = time.FixedZone("IST", 5*60*60+30*60)

type stockRow struct {
	ProductID       int64
	Name            string
	SKU             *string
	Category        *string
	StockQty        int
	ReorderLevel    int
	PriceInPaise    int64
	SoldLast30      int
	LastRestockedAt *time.Time
	ZeroSince       *time.Time
}

// LowStock returns every product at or below its reorder level.
//
// The two aggregates are LATERAL rather than joined-and-grouped: the outer
// query is already filtered to the handful of products that need attention, so
// this is a couple of index seeks per flagged row instead of scanning the whole
// movements ledger to throw almost all of it away.
func (r *Repository) LowStock(ctx context.Context) ([]stockRow, error) {
	tc := database.MustGetTenant(ctx)

	sql := `
		SELECT p.id AS product_id, p.name, p.sku, p.category,
		       p.stock_qty, p.reorder_level, p.price_in_paise,
		       COALESCE(sold.qty, 0) AS sold_last_30,
		       restock.at AS last_restocked_at,
		       zero.at     AS zero_since
		  FROM products p

		  -- What it sells. Two left is fine for something that moves twice a
		  -- year and an emergency for something that moves daily; without this
		  -- the reader has to know the product to read the row.
		  LEFT JOIN LATERAL (
		      SELECT COALESCE(SUM(-m.quantity), 0) AS qty
		        FROM stock_movements m
		       WHERE m.product_id = p.id
		         AND m.movement_type = 'sale'
		         AND m.created_at >= NOW() - INTERVAL '30 days'
		  ) sold ON true

		  LEFT JOIN LATERAL (
		      SELECT MAX(m.created_at) AS at
		        FROM stock_movements m
		       WHERE m.product_id = p.id AND m.quantity > 0
		  ) restock ON true

		  -- When it last hit zero, and only if it has not been positive since.
		  -- The ORDER BY/LIMIT finds the most recent crossing; the outer filter
		  -- in Go decides whether it still applies.
		  LEFT JOIN LATERAL (
		      SELECT m.created_at AS at
		        FROM stock_movements m
		       WHERE m.product_id = p.id AND m.qty_after <= 0
		       ORDER BY m.created_at DESC
		       LIMIT 1
		  ) zero ON true

		 WHERE p.gym_id = @gym
		   AND p.deleted_at IS NULL
		   AND p.is_active = true
		   AND p.stock_qty <= p.reorder_level

		 -- Out of stock first, then whatever is selling fastest: the product
		 -- you will run out of soonest is the one worth restocking first.
		 -- This orders products, never people.
		 ORDER BY (p.stock_qty <= 0) DESC, sold.qty DESC NULLS LAST, p.name ASC`

	var rows []stockRow
	err := r.db.WithContext(ctx).Raw(sql, map[string]interface{}{
		"gym": tc.GymID(),
	}).Scan(&rows).Error
	return rows, err
}

// ProductCount is the denominator. "2 of 11" reads very differently from "2".
func (r *Repository) ProductCount(ctx context.Context) (int, error) {
	tc := database.MustGetTenant(ctx)

	var n int64
	err := r.db.WithContext(ctx).
		Table("products").
		Where("gym_id = ? AND deleted_at IS NULL AND is_active = true", tc.GymID()).
		Count(&n).Error
	return int(n), err
}
