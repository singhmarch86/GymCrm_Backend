package invoicing

import "time"

// Invoice is a numbered tax document. See docs/FR-04-invoicing-discounts.md.
//
// An invoice is NOT a payment and NOT a renewal:
//
//	Invoice  → what is owed, as a document with a legal number
//	Payment  → money that actually arrived (internal/payments)
//	Renewal  → membership validity (internal/renewals)
//
// Once issued it is immutable (FR-04 §2.1). Corrections are made by cancelling
// and issuing a new one, so both documents survive for audit.
type Invoice struct {
	ID       int64 `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID    int64 `gorm:"not null"                json:"gym_id"`
	MemberID int64 `gorm:"not null"                json:"member_id"`

	// NULL while draft. Assigned atomically at issue time, never reused —
	// even by a cancelled invoice, which keeps its number deliberately.
	InvoiceNumber *string `gorm:"type:varchar(50)" json:"invoice_number,omitempty"`
	FinancialYear *string `gorm:"type:varchar(9)"  json:"financial_year,omitempty"`
	Status        string  `gorm:"type:varchar(20);not null;default:'draft'" json:"status"`

	InvoiceDate *time.Time `gorm:"type:date" json:"invoice_date,omitempty"`
	DueDate     *time.Time `gorm:"type:date" json:"due_date,omitempty"`

	// Snapshotted at issue so later settings changes never alter a document
	// already handed to a member.
	PlaceOfSupply    *string `gorm:"type:varchar(100)" json:"place_of_supply,omitempty"`
	GSTIN            *string `gorm:"type:varchar(20)"  json:"gstin,omitempty"`
	PricesIncludeTax bool    `gorm:"not null;default:false" json:"prices_include_tax"`

	DiscountID      *int64  `json:"discount_id,omitempty"`
	DiscountCode    *string `gorm:"type:varchar(50)"  json:"discount_code,omitempty"`
	DiscountLabel   *string `gorm:"type:varchar(150)" json:"discount_label,omitempty"`
	DiscountReason  *string `gorm:"type:text"         json:"discount_reason,omitempty"`
	DiscountInPaise int64   `gorm:"not null;default:0" json:"discount_in_paise"`

	SubtotalInPaise int64 `gorm:"not null;default:0" json:"subtotal_in_paise"`
	TaxInPaise      int64 `gorm:"not null;default:0" json:"tax_in_paise"`
	TotalInPaise    int64 `gorm:"not null;default:0" json:"total_in_paise"`

	Notes             *string    `gorm:"type:text" json:"notes,omitempty"`
	CancelledReason   *string    `gorm:"type:text" json:"cancelled_reason,omitempty"`
	CancelledAt       *time.Time `json:"cancelled_at,omitempty"`
	CancelledByUserID *int64     `json:"cancelled_by_user_id,omitempty"`
	CreatedByUserID   int64      `gorm:"not null" json:"created_by_user_id"`

	CreatedAt time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt time.Time `gorm:"autoUpdateTime" json:"updated_at"`
}

func (Invoice) TableName() string { return "invoices" }

// Invoice statuses. There is deliberately no "paid" status — payment state is
// derived from linked payments at read time (FR-04 §2).
const (
	StatusDraft     = "draft"
	StatusIssued    = "issued"
	StatusCancelled = "cancelled"
)

// Derived payment states, computed from linked payments — never stored.
const (
	PaymentStateUnpaid  = "unpaid"
	PaymentStatePartial = "partial"
	PaymentStatePaid    = "paid"
)

// InvoiceItem is one line of an invoice. Every field is a snapshot taken when
// the line was added: a later change to a plan's price must never rewrite a
// document that already exists (FR-04 §3).
type InvoiceItem struct {
	ID        int64 `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID     int64 `gorm:"not null"                json:"gym_id"`
	InvoiceID int64 `gorm:"not null"                json:"invoice_id"`

	Description string `gorm:"type:varchar(300);not null" json:"description"`
	ItemType    string `gorm:"type:varchar(20);not null;default:'custom'" json:"item_type"`
	// Deliberately not a foreign key — the source plan/package may be deleted
	// later and this line must survive unchanged.
	ReferenceID *int64 `json:"reference_id,omitempty"`

	Quantity         int     `gorm:"not null;default:1" json:"quantity"`
	UnitPriceInPaise int64   `gorm:"not null"           json:"unit_price_in_paise"`
	DiscountInPaise  int64   `gorm:"not null;default:0" json:"discount_in_paise"`
	TaxRatePct       float64 `gorm:"type:numeric(5,2);not null;default:18.00" json:"tax_rate_pct"`
	SACCode          *string `gorm:"type:varchar(10)" json:"sac_code,omitempty"`

	TaxInPaise       int64 `gorm:"not null;default:0" json:"tax_in_paise"`
	LineTotalInPaise int64 `gorm:"not null;default:0" json:"line_total_in_paise"`

	CreatedAt time.Time `gorm:"autoCreateTime" json:"created_at"`
}

func (InvoiceItem) TableName() string { return "invoice_items" }

// Item types.
const (
	ItemTypePlan      = "plan"
	ItemTypePTPackage = "pt_package"
	ItemTypeProduct   = "product"
	ItemTypeCustom    = "custom"
)

// Discount is a named reusable rule. Applying one snapshots its resolved paise
// value onto the invoice, so editing the rule later never changes a document
// already issued (FR-04 §4).
type Discount struct {
	ID           int64      `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID        int64      `gorm:"not null"                json:"gym_id"`
	Code         string     `gorm:"type:varchar(50);not null"  json:"code"`
	Name         string     `gorm:"type:varchar(150);not null" json:"name"`
	DiscountType string     `gorm:"type:varchar(10);not null"  json:"discount_type"`
	Value        float64    `gorm:"type:numeric(12,2);not null" json:"value"`
	ValidFrom    *time.Time `gorm:"type:date" json:"valid_from,omitempty"`
	ValidUntil   *time.Time `gorm:"type:date" json:"valid_until,omitempty"`
	MaxUses      *int       `json:"max_uses,omitempty"`
	TimesUsed    int        `gorm:"not null;default:0"    json:"times_used"`
	IsActive     bool       `gorm:"not null;default:true" json:"is_active"`
	CreatedAt    time.Time  `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt    time.Time  `gorm:"autoUpdateTime" json:"updated_at"`
}

func (Discount) TableName() string { return "discounts" }

// Discount types.
const (
	DiscountPercent = "percent"
	DiscountFlat    = "flat"
)

// BillingSettings holds per-gym invoicing configuration. A gym with no row
// falls back to the defaults applied in the service.
type BillingSettings struct {
	GymID            int64     `gorm:"primaryKey" json:"gym_id"`
	InvoicePrefix    string    `gorm:"type:varchar(20);not null;default:'INV'" json:"invoice_prefix"`
	GSTIN            *string   `gorm:"type:varchar(20)" json:"gstin,omitempty"`
	DefaultTaxRate   float64   `gorm:"type:numeric(5,2);not null;default:18.00" json:"default_tax_rate"`
	DefaultSACCode   *string   `gorm:"type:varchar(10)" json:"default_sac_code,omitempty"`
	PricesIncludeTax bool      `gorm:"not null;default:false" json:"prices_include_tax"`
	LegalName        *string   `gorm:"type:varchar(200)" json:"legal_name,omitempty"`
	AddressLine      *string   `gorm:"type:text"         json:"address_line,omitempty"`
	StateName        *string   `gorm:"type:varchar(100)" json:"state_name,omitempty"`
	CreatedAt        time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt        time.Time `gorm:"autoUpdateTime" json:"updated_at"`
}

func (BillingSettings) TableName() string { return "gym_billing_settings" }

// InvoiceSequence is the per-(gym, financial year) counter behind gapless
// numbering. Locked FOR UPDATE while issuing — FR-04 §1.1.
type InvoiceSequence struct {
	GymID         int64     `gorm:"primaryKey" json:"gym_id"`
	FinancialYear string    `gorm:"primaryKey;type:varchar(9)" json:"financial_year"`
	LastSeq       int       `gorm:"not null;default:0" json:"last_seq"`
	UpdatedAt     time.Time `gorm:"autoUpdateTime" json:"updated_at"`
}

func (InvoiceSequence) TableName() string { return "invoice_sequences" }
