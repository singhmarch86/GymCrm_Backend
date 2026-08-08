package pos

import "time"

// CreateProductRequest adds something to the shelf.
// @Description Create a product.
type CreateProductRequest struct {
	Name         string   `json:"name"`           // required
	SKU          string   `json:"sku"`            // optional, unique per gym
	Category     string   `json:"category"`
	Description  string   `json:"description"`
	PriceInPaise int64    `json:"price_in_paise"` // what the member pays
	CostInPaise  int64    `json:"cost_in_paise"`  // what the gym paid — drives margin
	TaxRatePct   *float64 `json:"tax_rate_pct"`   // defaults to 18
	ReorderLevel int      `json:"reorder_level"`
	// Recorded as a 'purchase' movement, so even the opening figure has a trail.
	OpeningStock int `json:"opening_stock"`
}

// UpdateProductRequest edits a product. Stock is deliberately absent — it moves
// only through recorded movements (FR-07 §1).
// @Description Edit a product. Stock is changed via stock adjustments, not here.
type UpdateProductRequest struct {
	Name         *string  `json:"name"`
	SKU          *string  `json:"sku"`
	Category     *string  `json:"category"`
	Description  *string  `json:"description"`
	PriceInPaise *int64   `json:"price_in_paise"`
	CostInPaise  *int64   `json:"cost_in_paise"`
	TaxRatePct   *float64 `json:"tax_rate_pct"`
	ReorderLevel *int     `json:"reorder_level"`
	IsActive     *bool    `json:"is_active"`
}

// AdjustStockRequest records a stock change with its reason.
// @Description Adjust stock. Positive adds, negative removes.
type AdjustStockRequest struct {
	Quantity     int    `json:"quantity"`      // required, non-zero, signed
	MovementType string `json:"movement_type"` // purchase|adjustment|return|wastage
	Reason       string `json:"reason"`
}

// SaleItemRequest is one line at the counter.
type SaleItemRequest struct {
	ProductID int64 `json:"product_id"`
	Quantity  int   `json:"quantity"`
}

// CreateSaleRequest records a completed counter transaction.
// @Description Record a sale. Stock is decremented atomically.
type CreateSaleRequest struct {
	MemberID        *int64            `json:"member_id"` // optional — walk-ins have none
	Items           []SaleItemRequest `json:"items"`     // required
	PaymentMode     string            `json:"payment_mode"`
	DiscountInPaise int64             `json:"discount_in_paise"`
	Notes           string            `json:"notes"`
}

// RefundRequest reverses a sale.
// @Description Refund a sale. Creates a reversing sale; the original is untouched.
type RefundRequest struct {
	Reason string `json:"reason"` // required
}

// ─── Responses ────────────────────────────────────────────────────────────────

type SaleItemResponse struct {
	ProductID        int64  `json:"product_id"`
	ProductName      string `json:"product_name"`
	Quantity         int    `json:"quantity"`
	UnitPriceInPaise int64  `json:"unit_price_in_paise"`
	LineTotalInPaise int64  `json:"line_total_in_paise"`
}

// SaleResponse is a completed transaction.
// @Description A sale.
type SaleResponse struct {
	ID              int64   `json:"id"`
	MemberID        *int64  `json:"member_id,omitempty"`
	MemberName      *string `json:"member_name,omitempty"`
	SubtotalInPaise int64   `json:"subtotal_in_paise"`
	TaxInPaise      int64   `json:"tax_in_paise"`
	DiscountInPaise int64   `json:"discount_in_paise"`
	TotalInPaise    int64   `json:"total_in_paise"`
	TotalInRupees   float64 `json:"total_in_rupees"`
	PaymentMode     string  `json:"payment_mode"`
	IsRefund        bool    `json:"is_refund"`
	RefundOfSaleID  *int64  `json:"refund_of_sale_id,omitempty"`
	Reason          *string `json:"reason,omitempty"`

	CreatedAt time.Time          `json:"created_at"`
	Items     []SaleItemResponse `json:"items"`
}

// SummaryResponse is the retail dashboard: what sold, what it cost, what's left.
// @Description Retail summary for a period.
type SummaryResponse struct {
	SaleCount         int64   `json:"sale_count"`
	UnitsSold         int64   `json:"units_sold"`
	RevenueInPaise    int64   `json:"revenue_in_paise"`
	RevenueInRupees   float64 `json:"revenue_in_rupees"`
	CostInPaise       int64   `json:"cost_in_paise"`
	MarginInPaise     int64   `json:"margin_in_paise"`
	StockValueInPaise int64   `json:"stock_value_in_paise"`
	LowStockCount     int64   `json:"low_stock_count"`
}
