package pos

import "time"

// Retail: products, stock movements, sales. See docs/FR-07-pos-inventory.md.

// Product is something the gym sells. StockQty is maintained by movements and
// is never written directly by application code (FR-07 §1).
type Product struct {
	ID          int64   `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID       int64   `gorm:"not null" json:"gym_id"`
	SKU         *string `gorm:"type:varchar(60)" json:"sku,omitempty"`
	Name        string  `gorm:"type:varchar(200);not null" json:"name"`
	Category    *string `gorm:"type:varchar(80)" json:"category,omitempty"`
	Description *string `gorm:"type:text" json:"description,omitempty"`

	PriceInPaise int64   `gorm:"not null" json:"price_in_paise"`
	CostInPaise  int64   `gorm:"not null;default:0" json:"cost_in_paise"`
	TaxRatePct   float64 `gorm:"type:numeric(5,2);not null;default:18.00" json:"tax_rate_pct"`

	StockQty     int `gorm:"not null;default:0" json:"stock_qty"`
	ReorderLevel int `gorm:"not null;default:0" json:"reorder_level"`

	IsActive  bool       `gorm:"not null;default:true" json:"is_active"`
	CreatedAt time.Time  `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt time.Time  `gorm:"autoUpdateTime" json:"updated_at"`
	DeletedAt *time.Time `json:"-"`
}

func (Product) TableName() string { return "products" }

// IsLowStock drives the one report that actually prevents lost sales.
func (p *Product) IsLowStock() bool { return p.StockQty <= p.ReorderLevel }

// StockMovement is an insert-only record of why a stock level changed.
// Quantity is signed: positive adds, negative removes.
type StockMovement struct {
	ID           int64  `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID        int64  `gorm:"not null" json:"gym_id"`
	ProductID    int64  `gorm:"not null" json:"product_id"`
	MovementType string `gorm:"type:varchar(20);not null" json:"movement_type"`
	Quantity     int    `gorm:"not null" json:"quantity"`
	QtyAfter     int    `gorm:"not null" json:"qty_after"`

	Reason          *string   `gorm:"type:text" json:"reason,omitempty"`
	SaleID          *int64    `json:"sale_id,omitempty"`
	CreatedByUserID int64     `gorm:"not null" json:"created_by_user_id"`
	CreatedAt       time.Time `gorm:"autoCreateTime" json:"created_at"`
}

func (StockMovement) TableName() string { return "stock_movements" }

// Movement types.
const (
	MovementPurchase   = "purchase"
	MovementSale       = "sale"
	MovementAdjustment = "adjustment"
	MovementReturn     = "return"
	MovementWastage    = "wastage"
)

// Sale is a completed counter transaction. There is no draft state — a sale
// exists only once it has happened (FR-07 §2).
type Sale struct {
	ID       int64  `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID    int64  `gorm:"not null" json:"gym_id"`
	MemberID *int64 `json:"member_id,omitempty"`

	SaleNumber       *string `gorm:"type:varchar(50)" json:"sale_number,omitempty"`
	SubtotalInPaise  int64   `gorm:"not null;default:0" json:"subtotal_in_paise"`
	TaxInPaise       int64   `gorm:"not null;default:0" json:"tax_in_paise"`
	DiscountInPaise  int64   `gorm:"not null;default:0" json:"discount_in_paise"`
	TotalInPaise     int64   `gorm:"not null;default:0" json:"total_in_paise"`

	PaymentMode     string  `gorm:"type:varchar(20);not null;default:'cash'" json:"payment_mode"`
	IsRefund        bool    `gorm:"not null;default:false" json:"is_refund"`
	RefundOfSaleID  *int64  `json:"refund_of_sale_id,omitempty"`
	Reason          *string `gorm:"type:text" json:"reason,omitempty"`

	InvoiceID       *int64    `json:"invoice_id,omitempty"`
	Notes           *string   `gorm:"type:text" json:"notes,omitempty"`
	CreatedByUserID int64     `gorm:"not null" json:"created_by_user_id"`
	CreatedAt       time.Time `gorm:"autoCreateTime" json:"created_at"`
}

func (Sale) TableName() string { return "sales" }

// SaleItem is one line, snapshotting the product's name, price and cost at the
// moment of sale so later changes never rewrite a completed transaction.
type SaleItem struct {
	ID        int64 `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID     int64 `gorm:"not null" json:"gym_id"`
	SaleID    int64 `gorm:"not null" json:"sale_id"`
	ProductID int64 `gorm:"not null" json:"product_id"`

	ProductName      string  `gorm:"type:varchar(200);not null" json:"product_name"`
	UnitPriceInPaise int64   `gorm:"not null" json:"unit_price_in_paise"`
	CostInPaise      int64   `gorm:"not null;default:0" json:"cost_in_paise"`
	TaxRatePct       float64 `gorm:"type:numeric(5,2);not null;default:18.00" json:"tax_rate_pct"`

	Quantity         int   `gorm:"not null" json:"quantity"`
	LineTotalInPaise int64 `gorm:"not null;default:0" json:"line_total_in_paise"`

	CreatedAt time.Time `gorm:"autoCreateTime" json:"created_at"`
}

func (SaleItem) TableName() string { return "sale_items" }

// Payment modes. 'account' means paying from the member's stored wallet credit,
// which is debited inside the same transaction as the sale (FR-08).
const (
	PaymentModeCash    = "cash"
	PaymentModeUPI     = "upi"
	PaymentModeAccount = "account"
)
