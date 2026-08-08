package invoicing

import "time"

// ─── Invoice requests ─────────────────────────────────────────────────────────

// CreateInvoiceRequest opens a draft. Lines are added separately so staff can
// build an invoice up incrementally, which is how a front desk actually works.
// @Description Create a draft invoice for a member.
type CreateInvoiceRequest struct {
	MemberID int64  `json:"member_id"` // required
	DueDate  string `json:"due_date"`  // optional, YYYY-MM-DD
	Notes    string `json:"notes"`     // optional
	Items    []AddItemRequest `json:"items"` // optional — convenience for one-shot creation
}

// AddItemRequest appends a line to a draft invoice.
// @Description Add a line item to a draft invoice.
type AddItemRequest struct {
	Description      string   `json:"description"`         // required
	ItemType         string   `json:"item_type"`           // optional: plan|pt_package|product|custom
	ReferenceID      *int64   `json:"reference_id"`        // optional
	Quantity         int      `json:"quantity"`            // optional, defaults to 1
	UnitPriceInPaise int64    `json:"unit_price_in_paise"` // required, >= 0
	DiscountInPaise  int64    `json:"discount_in_paise"`   // optional
	TaxRatePct       *float64 `json:"tax_rate_pct"`        // optional, defaults to gym setting
	SACCode          string   `json:"sac_code"`            // optional
}

// AddPlanItemRequest adds a line from the plan catalogue, snapshotting the
// plan's current name and price. Convenience over AddItemRequest so the client
// never has to trust its own cached plan price.
// @Description Add a line item sourced from a membership plan.
type AddPlanItemRequest struct {
	PlanID   int64 `json:"plan_id"`  // required
	Quantity int   `json:"quantity"` // optional, defaults to 1
}

// ApplyDiscountRequest applies either a coded discount or an ad-hoc amount.
// Exactly one of code / ad_hoc_in_paise should be provided.
// @Description Apply a discount to a draft invoice.
type ApplyDiscountRequest struct {
	Code           string `json:"code"`             // optional — a discounts.code
	AdHocInPaise   int64  `json:"ad_hoc_in_paise"`  // optional — one-off negotiated amount
	Reason         string `json:"reason"`           // required for ad-hoc
}

// IssueInvoiceRequest turns a draft into a numbered document.
// @Description Issue a draft invoice, assigning its permanent number.
type IssueInvoiceRequest struct {
	InvoiceDate string `json:"invoice_date"` // optional, YYYY-MM-DD, defaults to today
}

// CancelInvoiceRequest voids an issued invoice. Reason is mandatory — a
// cancelled tax document with no explanation is useless to an auditor.
// @Description Cancel an issued invoice. The number is retained, never reused.
type CancelInvoiceRequest struct {
	Reason string `json:"reason"` // required
}

// ─── Discount requests ────────────────────────────────────────────────────────

// CreateDiscountRequest defines a reusable discount rule.
// @Description Create a discount rule.
type CreateDiscountRequest struct {
	Code         string  `json:"code"`          // required, unique per gym
	Name         string  `json:"name"`          // required
	DiscountType string  `json:"discount_type"` // required: percent | flat
	Value        float64 `json:"value"`         // percent: 0-100 | flat: paise
	ValidFrom    string  `json:"valid_from"`    // optional, YYYY-MM-DD
	ValidUntil   string  `json:"valid_until"`   // optional, YYYY-MM-DD
	MaxUses      *int    `json:"max_uses"`      // optional, NULL = unlimited
}

// UpdateDiscountRequest edits a rule. Only provided fields change. Never
// affects invoices already issued with this discount.
// @Description Edit a discount rule.
type UpdateDiscountRequest struct {
	Name       *string  `json:"name"`
	Value      *float64 `json:"value"`
	ValidFrom  *string  `json:"valid_from"`
	ValidUntil *string  `json:"valid_until"`
	MaxUses    *int     `json:"max_uses"`
	IsActive   *bool    `json:"is_active"`
}

// ─── Settings ─────────────────────────────────────────────────────────────────

// UpdateBillingSettingsRequest configures per-gym invoicing.
// @Description Update this gym's invoicing settings.
type UpdateBillingSettingsRequest struct {
	InvoicePrefix    *string  `json:"invoice_prefix"`
	GSTIN            *string  `json:"gstin"`
	DefaultTaxRate   *float64 `json:"default_tax_rate"`
	DefaultSACCode   *string  `json:"default_sac_code"`
	PricesIncludeTax *bool    `json:"prices_include_tax"`
	LegalName        *string  `json:"legal_name"`
	AddressLine      *string  `json:"address_line"`
	StateName        *string  `json:"state_name"`
}

// ─── Responses ────────────────────────────────────────────────────────────────

// InvoiceItemResponse is one line with its computed amounts.
// @Description An invoice line item.
type InvoiceItemResponse struct {
	ID                int64   `json:"id"`
	Description       string  `json:"description"`
	ItemType          string  `json:"item_type"`
	ReferenceID       *int64  `json:"reference_id,omitempty"`
	Quantity          int     `json:"quantity"`
	UnitPriceInPaise  int64   `json:"unit_price_in_paise"`
	UnitPriceInRupees float64 `json:"unit_price_in_rupees"`
	DiscountInPaise   int64   `json:"discount_in_paise"`
	TaxRatePct        float64 `json:"tax_rate_pct"`
	SACCode           *string `json:"sac_code,omitempty"`
	TaxInPaise        int64   `json:"tax_in_paise"`
	LineTotalInPaise  int64   `json:"line_total_in_paise"`
	LineTotalInRupees float64 `json:"line_total_in_rupees"`
}

// InvoiceResponse is a full invoice with lines, totals, GST split and the
// derived payment state.
// @Description A full invoice document.
type InvoiceResponse struct {
	ID            int64   `json:"id"`
	MemberID      int64   `json:"member_id"`
	MemberName    string  `json:"member_name"`
	MemberPhone   string  `json:"member_phone"`
	InvoiceNumber *string `json:"invoice_number,omitempty"`
	FinancialYear *string `json:"financial_year,omitempty"`
	Status        string  `json:"status"`

	// Derived from linked payments, never stored — FR-04 §2.
	PaymentState  string `json:"payment_state"`
	PaidInPaise   int64  `json:"paid_in_paise"`
	DueInPaise    int64  `json:"due_in_paise"`

	InvoiceDate *time.Time `json:"invoice_date,omitempty"`
	DueDate     *time.Time `json:"due_date,omitempty"`

	PlaceOfSupply    *string `json:"place_of_supply,omitempty"`
	GSTIN            *string `json:"gstin,omitempty"`
	PricesIncludeTax bool    `json:"prices_include_tax"`

	DiscountCode    *string `json:"discount_code,omitempty"`
	DiscountLabel   *string `json:"discount_label,omitempty"`
	DiscountReason  *string `json:"discount_reason,omitempty"`
	DiscountInPaise int64   `json:"discount_in_paise"`

	SubtotalInPaise int64   `json:"subtotal_in_paise"`
	TaxInPaise      int64   `json:"tax_in_paise"`
	TotalInPaise    int64   `json:"total_in_paise"`
	TotalInRupees   float64 `json:"total_in_rupees"`

	// Intra-state split for display. Derived, not stored — FR-04 §3.2.
	CGSTInPaise int64 `json:"cgst_in_paise"`
	SGSTInPaise int64 `json:"sgst_in_paise"`

	Notes           *string    `json:"notes,omitempty"`
	CancelledReason *string    `json:"cancelled_reason,omitempty"`
	CancelledAt     *time.Time `json:"cancelled_at,omitempty"`
	CreatedAt       time.Time  `json:"created_at"`

	Items []InvoiceItemResponse `json:"items"`
}

// InvoiceSummaryResponse is the list-view shape — no line items.
// @Description An invoice as it appears in a list.
type InvoiceSummaryResponse struct {
	ID            int64      `json:"id"`
	MemberID      int64      `json:"member_id"`
	MemberName    string     `json:"member_name"`
	InvoiceNumber *string    `json:"invoice_number,omitempty"`
	Status        string     `json:"status"`
	PaymentState  string     `json:"payment_state"`
	InvoiceDate   *time.Time `json:"invoice_date,omitempty"`
	DueDate       *time.Time `json:"due_date,omitempty"`
	TotalInPaise  int64      `json:"total_in_paise"`
	TotalInRupees float64    `json:"total_in_rupees"`
	PaidInPaise   int64      `json:"paid_in_paise"`
	DueInPaise    int64      `json:"due_in_paise"`
	CreatedAt     time.Time  `json:"created_at"`
}

// DiscountResponse is a discount rule.
// @Description A discount rule.
type DiscountResponse struct {
	ID           int64      `json:"id"`
	Code         string     `json:"code"`
	Name         string     `json:"name"`
	DiscountType string     `json:"discount_type"`
	Value        float64    `json:"value"`
	ValidFrom    *time.Time `json:"valid_from,omitempty"`
	ValidUntil   *time.Time `json:"valid_until,omitempty"`
	MaxUses      *int       `json:"max_uses,omitempty"`
	TimesUsed    int        `json:"times_used"`
	IsActive     bool       `json:"is_active"`
	CreatedAt    time.Time  `json:"created_at"`
}

// BillingSettingsResponse is this gym's invoicing configuration.
// @Description Per-gym invoicing settings.
type BillingSettingsResponse struct {
	GymID            int64   `json:"gym_id"`
	InvoicePrefix    string  `json:"invoice_prefix"`
	GSTIN            *string `json:"gstin,omitempty"`
	DefaultTaxRate   float64 `json:"default_tax_rate"`
	DefaultSACCode   *string `json:"default_sac_code,omitempty"`
	PricesIncludeTax bool    `json:"prices_include_tax"`
	LegalName        *string `json:"legal_name,omitempty"`
	AddressLine      *string `json:"address_line,omitempty"`
	StateName        *string `json:"state_name,omitempty"`
}
