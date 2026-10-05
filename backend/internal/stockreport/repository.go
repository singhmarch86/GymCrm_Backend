package stockreport

import (
	"context"

	"gorm.io/gorm"

	"gymcrm/internal/database"
)

type Repository struct{ db *gorm.DB }

func NewRepository(db *gorm.DB) *Repository { return &Repository{db: db} }

type productRow struct {
	ProductID         int64
	Name              string
	SKU               string
	Category          string
	StockQty          int
	ReorderLevel      int
	CostInPaise       int64
	UnitsSold         int
	RevenueInPaise    int64
	ProfitInPaise     int64
	StockValueInPaise int64
}

// Products returns every active product with what it did over the window.
//
// LEFT JOIN, not INNER: a product that sold nothing is the most interesting
// row on this report, and an inner join would silently drop exactly the stock
// the owner is losing money on.
//
// Profit uses the cost snapshotted on each sale line rather than the product's
// cost today. A supplier price rise must not rewrite what last month actually
// earned.
//
// Refunds are excluded. A returned item is not a sale, and counting it would
// overstate both the rate and the profit.
func (r *Repository) Products(
	ctx context.Context, from, to string,
) ([]productRow, error) {
	tc := database.MustGetTenant(ctx)

	var rows []productRow
	err := r.db.WithContext(ctx).Raw(`
		SELECT p.id AS product_id,
		       p.name,
		       COALESCE(p.sku, '') AS sku,
		       COALESCE(p.category, '') AS category,
		       p.stock_qty,
		       p.reorder_level,
		       p.cost_in_paise,
		       COALESCE(sold.units, 0)   AS units_sold,
		       COALESCE(sold.revenue, 0) AS revenue_in_paise,
		       COALESCE(sold.profit, 0)  AS profit_in_paise,
		       (p.stock_qty * p.cost_in_paise) AS stock_value_in_paise
		  FROM products p
		  LEFT JOIN LATERAL (
		      SELECT SUM(si.quantity) AS units,
		             SUM(si.line_total_in_paise) AS revenue,
		             SUM(si.quantity *
		                 (si.unit_price_in_paise - si.cost_in_paise)) AS profit
		        FROM sale_items si
		        JOIN sales s ON s.id = si.sale_id
		       WHERE si.product_id = p.id
		         AND s.gym_id = @gym
		         AND s.is_refund = false
		         AND (s.created_at AT TIME ZONE 'Asia/Kolkata')::date
		             BETWEEN CAST(@from AS date) AND CAST(@to AS date)
		  ) sold ON true
		 WHERE p.gym_id = @gym
		   AND p.is_active = true
		 ORDER BY COALESCE(sold.profit, 0) DESC, p.name ASC`,
		map[string]interface{}{
			"gym": tc.GymID(), "from": from, "to": to,
		}).Scan(&rows).Error
	return rows, err
}
