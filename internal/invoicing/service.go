package invoicing

import (
	"context"
	"fmt"
	"strings"
	"time"

	"gymcrm/internal/database"
)

// Service holds invoicing and discount logic. Rules are specified in
// docs/FR-04-invoicing-discounts.md.
//
// The one rule everything else hangs off: a draft is freely editable, an issued
// invoice is frozen. Every mutating method below starts by asserting that.
type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

// Fallback settings for a gym that has never configured billing.
const (
	defaultPrefix  = "INV"
	defaultTaxRate = 18.00
	defaultSAC     = "999723" // SAC for fitness/health club services in India

	// Indian gyms quote all-in and collect the advertised figure, so prices are
	// treated as tax-inclusive by default: the tax is carved out of the price
	// rather than added on top. Exclusive would make every invoice total exceed
	// the payment actually collected, leaving invoices permanently "part paid"
	// (FR-04 §5.3, migration 018). Gyms selling B2B can switch per-gym.
	defaultPricesIncludeTax = true
)

func (s *Service) settings(ctx context.Context) (*BillingSettings, error) {
	st, err := s.repo.GetSettings(ctx)
	if err != nil {
		return nil, err
	}
	if st != nil {
		return st, nil
	}
	sac := defaultSAC
	return &BillingSettings{
		InvoicePrefix:    defaultPrefix,
		DefaultTaxRate:   defaultTaxRate,
		DefaultSACCode:   &sac,
		PricesIncludeTax: defaultPricesIncludeTax,
	}, nil
}

// ─── Invoices ─────────────────────────────────────────────────────────────────

func (s *Service) CreateInvoice(ctx context.Context, req CreateInvoiceRequest) (*InvoiceResponse, error) {
	if req.MemberID <= 0 {
		return nil, ErrMemberNotFound
	}
	exists, err := s.repo.memberExists(ctx, req.MemberID)
	if err != nil {
		return nil, fmt.Errorf("create invoice: member lookup: %w", err)
	}
	if !exists {
		return nil, ErrMemberNotFound
	}

	dueDate, err := parseDate(req.DueDate)
	if err != nil {
		return nil, err
	}
	st, err := s.settings(ctx)
	if err != nil {
		return nil, fmt.Errorf("create invoice: settings: %w", err)
	}
	tc := database.MustGetTenant(ctx)

	inv := &Invoice{
		GymID:            tc.GymID(),
		MemberID:         req.MemberID,
		Status:           StatusDraft,
		DueDate:          dueDate,
		PricesIncludeTax: st.PricesIncludeTax,
		Notes:            optionalText(req.Notes),
		CreatedByUserID:  tc.UserID(),
	}
	if err := s.repo.CreateInvoice(ctx, inv); err != nil {
		return nil, fmt.Errorf("create invoice: %w", err)
	}

	// Convenience: accept lines inline so a simple sale is one call.
	for i := range req.Items {
		if _, err := s.addItem(ctx, inv, &req.Items[i], st); err != nil {
			return nil, err
		}
	}
	if len(req.Items) > 0 {
		if err := s.repo.RecalculateTotals(ctx, inv.ID); err != nil {
			return nil, fmt.Errorf("create invoice: totals: %w", err)
		}
	}
	return s.GetInvoice(ctx, inv.ID)
}

func (s *Service) GetInvoice(ctx context.Context, id int64) (*InvoiceResponse, error) {
	row, err := s.repo.invoiceRowByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("get invoice: %w", err)
	}
	if row == nil {
		return nil, ErrInvoiceNotFound
	}
	items, err := s.repo.ListItems(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("get invoice: items: %w", err)
	}
	resp := toInvoiceResponse(*row, items)
	return &resp, nil
}

func (s *Service) ListInvoices(ctx context.Context, memberID *int64, status string) ([]InvoiceSummaryResponse, error) {
	rows, err := s.repo.ListInvoices(ctx, memberID, status)
	if err != nil {
		return nil, fmt.Errorf("list invoices: %w", err)
	}
	out := make([]InvoiceSummaryResponse, 0, len(rows))
	for _, r := range rows {
		out = append(out, toSummaryResponse(r))
	}
	return out, nil
}

// requireDraft is the gate in front of every mutation. Issued invoices are
// immutable — FR-04 §2.1.
func (s *Service) requireDraft(ctx context.Context, id int64) (*Invoice, error) {
	inv, err := s.repo.FindInvoice(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("load invoice: %w", err)
	}
	if inv == nil {
		return nil, ErrInvoiceNotFound
	}
	if inv.Status != StatusDraft {
		return nil, ErrInvoiceNotDraft
	}
	return inv, nil
}

func (s *Service) AddItem(ctx context.Context, invoiceID int64, req AddItemRequest) (*InvoiceResponse, error) {
	inv, err := s.requireDraft(ctx, invoiceID)
	if err != nil {
		return nil, err
	}
	st, err := s.settings(ctx)
	if err != nil {
		return nil, err
	}
	if _, err := s.addItem(ctx, inv, &req, st); err != nil {
		return nil, err
	}
	if err := s.repo.RecalculateTotals(ctx, invoiceID); err != nil {
		return nil, fmt.Errorf("add item: totals: %w", err)
	}
	return s.GetInvoice(ctx, invoiceID)
}

// AddPlanItem snapshots a plan's current name and price onto a line. The
// client never supplies the price — the catalogue is the source of truth at
// the moment the line is added, and frozen thereafter (FR-04 §3).
func (s *Service) AddPlanItem(ctx context.Context, invoiceID int64, req AddPlanItemRequest) (*InvoiceResponse, error) {
	inv, err := s.requireDraft(ctx, invoiceID)
	if err != nil {
		return nil, err
	}
	plan, err := s.repo.findPlan(ctx, req.PlanID)
	if err != nil {
		return nil, fmt.Errorf("add plan item: %w", err)
	}
	if plan == nil {
		return nil, fmt.Errorf("plan not found")
	}
	st, err := s.settings(ctx)
	if err != nil {
		return nil, err
	}
	planID := req.PlanID
	item := AddItemRequest{
		Description:      plan.Name,
		ItemType:         ItemTypePlan,
		ReferenceID:      &planID,
		Quantity:         req.Quantity,
		UnitPriceInPaise: plan.PriceInPaise,
	}
	if _, err := s.addItem(ctx, inv, &item, st); err != nil {
		return nil, err
	}
	if err := s.repo.RecalculateTotals(ctx, invoiceID); err != nil {
		return nil, fmt.Errorf("add plan item: totals: %w", err)
	}
	return s.GetInvoice(ctx, invoiceID)
}

func (s *Service) addItem(ctx context.Context, inv *Invoice, req *AddItemRequest, st *BillingSettings) (*InvoiceItem, error) {
	if err := validateAddItem(req); err != nil {
		return nil, err
	}
	rate := st.DefaultTaxRate
	if req.TaxRatePct != nil {
		rate = *req.TaxRatePct
	}
	sac := st.DefaultSACCode
	if strings.TrimSpace(req.SACCode) != "" {
		v := strings.TrimSpace(req.SACCode)
		sac = &v
	}

	_, _, tax, lineTotal := lineAmounts(
		req.UnitPriceInPaise, req.Quantity, req.DiscountInPaise, rate, inv.PricesIncludeTax,
	)

	item := &InvoiceItem{
		GymID:            inv.GymID,
		InvoiceID:        inv.ID,
		Description:      strings.TrimSpace(req.Description),
		ItemType:         req.ItemType,
		ReferenceID:      req.ReferenceID,
		Quantity:         req.Quantity,
		UnitPriceInPaise: req.UnitPriceInPaise,
		DiscountInPaise:  req.DiscountInPaise,
		TaxRatePct:       rate,
		SACCode:          sac,
		TaxInPaise:       tax,
		LineTotalInPaise: lineTotal,
	}
	if err := s.repo.CreateItem(ctx, item); err != nil {
		return nil, fmt.Errorf("add item: %w", err)
	}
	return item, nil
}

func (s *Service) RemoveItem(ctx context.Context, invoiceID, itemID int64) (*InvoiceResponse, error) {
	if _, err := s.requireDraft(ctx, invoiceID); err != nil {
		return nil, err
	}
	n, err := s.repo.DeleteItem(ctx, invoiceID, itemID)
	if err != nil {
		return nil, fmt.Errorf("remove item: %w", err)
	}
	if n == 0 {
		return nil, ErrItemNotFound
	}
	if err := s.repo.RecalculateTotals(ctx, invoiceID); err != nil {
		return nil, fmt.Errorf("remove item: totals: %w", err)
	}
	return s.GetInvoice(ctx, invoiceID)
}

// ApplyDiscount attaches either a coded rule or an ad-hoc negotiated amount.
// The resolved paise value is snapshotted now; the rule may change later, this
// document may not (FR-04 §4).
func (s *Service) ApplyDiscount(ctx context.Context, invoiceID int64, req ApplyDiscountRequest) (*InvoiceResponse, error) {
	inv, err := s.requireDraft(ctx, invoiceID)
	if err != nil {
		return nil, err
	}

	// Base the discount on the current line total, before any previous
	// invoice-level discount — otherwise re-applying compounds it.
	items, err := s.repo.ListItems(ctx, invoiceID)
	if err != nil {
		return nil, fmt.Errorf("apply discount: items: %w", err)
	}
	var base int64
	for _, it := range items {
		base += it.LineTotalInPaise
	}

	fields := map[string]any{}

	switch {
	case strings.TrimSpace(req.Code) != "":
		d, err := s.repo.FindDiscountByCode(ctx, req.Code)
		if err != nil {
			return nil, fmt.Errorf("apply discount: %w", err)
		}
		if d == nil {
			return nil, ErrDiscountNotFound
		}
		if err := checkDiscountUsable(d, today()); err != nil {
			return nil, err
		}
		fields["discount_id"] = d.ID
		fields["discount_code"] = d.Code
		fields["discount_label"] = d.Name
		fields["discount_in_paise"] = resolveDiscount(d, base)
		fields["discount_reason"] = optionalText(req.Reason)

	case req.AdHocInPaise > 0:
		// A one-off negotiated amount still has to be explainable later.
		if strings.TrimSpace(req.Reason) == "" {
			return nil, fmt.Errorf("a reason is required for an ad-hoc discount")
		}
		v := req.AdHocInPaise
		if v > base {
			v = base
		}
		fields["discount_id"] = nil
		fields["discount_code"] = nil
		fields["discount_label"] = "Ad-hoc discount"
		fields["discount_in_paise"] = v
		fields["discount_reason"] = strings.TrimSpace(req.Reason)

	default:
		// Clearing the discount.
		fields["discount_id"] = nil
		fields["discount_code"] = nil
		fields["discount_label"] = nil
		fields["discount_reason"] = nil
		fields["discount_in_paise"] = 0
	}

	if err := s.repo.UpdateInvoiceFields(ctx, inv.ID, fields); err != nil {
		return nil, fmt.Errorf("apply discount: %w", err)
	}
	if err := s.repo.RecalculateTotals(ctx, invoiceID); err != nil {
		return nil, fmt.Errorf("apply discount: totals: %w", err)
	}
	return s.GetInvoice(ctx, invoiceID)
}

// Issue assigns the permanent number. See Repository.IssueInvoice for why the
// numbering is transactional.
func (s *Service) Issue(ctx context.Context, invoiceID int64, req IssueInvoiceRequest) (*InvoiceResponse, error) {
	inv, err := s.requireDraft(ctx, invoiceID)
	if err != nil {
		return nil, err
	}
	items, err := s.repo.ListItems(ctx, invoiceID)
	if err != nil {
		return nil, fmt.Errorf("issue: items: %w", err)
	}
	if len(items) == 0 {
		return nil, ErrInvoiceHasNoItems
	}

	invoiceDate := today()
	if d, err := parseDate(req.InvoiceDate); err != nil {
		return nil, err
	} else if d != nil {
		invoiceDate = *d
	}

	st, err := s.settings(ctx)
	if err != nil {
		return nil, err
	}

	// Snapshot the gym's identity onto the document so a later settings change
	// never rewrites an invoice already issued.
	snapshot := map[string]any{
		"gstin":           st.GSTIN,
		"place_of_supply": st.StateName,
	}

	if _, _, err := s.repo.IssueInvoice(ctx, invoiceID, invoiceDate, st.InvoicePrefix, snapshot); err != nil {
		return nil, fmt.Errorf("issue: %w", err)
	}

	// Usage counts on issue, never on draft, and only once (FR-04 §4 rule 4).
	if inv.DiscountID != nil {
		if err := s.repo.IncrementDiscountUsage(ctx, *inv.DiscountID); err != nil {
			return nil, fmt.Errorf("issue: discount usage: %w", err)
		}
	}
	return s.GetInvoice(ctx, invoiceID)
}

// Cancel voids an issued invoice. The number is kept deliberately — an auditor
// expects to see a cancelled document, not a missing one.
func (s *Service) Cancel(ctx context.Context, invoiceID int64, req CancelInvoiceRequest) (*InvoiceResponse, error) {
	if err := validateCancel(req); err != nil {
		return nil, err
	}
	inv, err := s.repo.FindInvoice(ctx, invoiceID)
	if err != nil {
		return nil, fmt.Errorf("cancel: %w", err)
	}
	if inv == nil {
		return nil, ErrInvoiceNotFound
	}
	if inv.Status == StatusCancelled {
		return nil, ErrInvoiceCancelled
	}
	if inv.Status != StatusIssued {
		return nil, ErrInvoiceNotIssued
	}

	tc := database.MustGetTenant(ctx)
	now := time.Now()
	userID := tc.UserID()
	if err := s.repo.UpdateInvoiceFields(ctx, invoiceID, map[string]any{
		"status":               StatusCancelled,
		"cancelled_reason":     strings.TrimSpace(req.Reason),
		"cancelled_at":         now,
		"cancelled_by_user_id": userID,
	}); err != nil {
		return nil, fmt.Errorf("cancel: %w", err)
	}
	return s.GetInvoice(ctx, invoiceID)
}

// DeleteDraft removes a draft outright. Deliberately only drafts: a draft never
// burned a number, so nothing is lost from the series (FR-04 §1 rule 2).
func (s *Service) DeleteDraft(ctx context.Context, invoiceID int64) error {
	if _, err := s.requireDraft(ctx, invoiceID); err != nil {
		return err
	}
	if err := s.repo.DeleteDraft(ctx, invoiceID); err != nil {
		return fmt.Errorf("delete draft: %w", err)
	}
	return nil
}

// ─── Discounts ────────────────────────────────────────────────────────────────

func (s *Service) CreateDiscount(ctx context.Context, req CreateDiscountRequest) (*DiscountResponse, error) {
	validFrom, validUntil, err := validateCreateDiscount(req)
	if err != nil {
		return nil, err
	}
	existing, err := s.repo.FindDiscountByCode(ctx, req.Code)
	if err != nil {
		return nil, fmt.Errorf("create discount: %w", err)
	}
	if existing != nil {
		return nil, ErrDiscountCodeTaken
	}

	tc := database.MustGetTenant(ctx)
	d := &Discount{
		GymID:        tc.GymID(),
		Code:         strings.TrimSpace(req.Code),
		Name:         strings.TrimSpace(req.Name),
		DiscountType: req.DiscountType,
		Value:        req.Value,
		ValidFrom:    validFrom,
		ValidUntil:   validUntil,
		MaxUses:      req.MaxUses,
		IsActive:     true,
	}
	if err := s.repo.CreateDiscount(ctx, d); err != nil {
		return nil, fmt.Errorf("create discount: %w", err)
	}
	resp := toDiscountResponse(*d)
	return &resp, nil
}

func (s *Service) ListDiscounts(ctx context.Context, activeOnly bool) ([]DiscountResponse, error) {
	rows, err := s.repo.ListDiscounts(ctx, activeOnly)
	if err != nil {
		return nil, fmt.Errorf("list discounts: %w", err)
	}
	out := make([]DiscountResponse, 0, len(rows))
	for _, d := range rows {
		out = append(out, toDiscountResponse(d))
	}
	return out, nil
}

func (s *Service) UpdateDiscount(ctx context.Context, id int64, req UpdateDiscountRequest) (*DiscountResponse, error) {
	existing, err := s.repo.FindDiscount(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("update discount: %w", err)
	}
	if existing == nil {
		return nil, ErrDiscountNotFound
	}

	fields := map[string]any{}
	if req.Name != nil {
		if strings.TrimSpace(*req.Name) == "" {
			return nil, ErrDiscountNameMissing
		}
		fields["name"] = strings.TrimSpace(*req.Name)
	}
	if req.Value != nil {
		if *req.Value < 0 || (existing.DiscountType == DiscountPercent && *req.Value > 100) {
			return nil, ErrDiscountValueRange
		}
		fields["value"] = *req.Value
	}
	if req.ValidFrom != nil {
		d, err := parseDate(*req.ValidFrom)
		if err != nil {
			return nil, err
		}
		fields["valid_from"] = d
	}
	if req.ValidUntil != nil {
		d, err := parseDate(*req.ValidUntil)
		if err != nil {
			return nil, err
		}
		fields["valid_until"] = d
	}
	if req.MaxUses != nil {
		fields["max_uses"] = *req.MaxUses
	}
	if req.IsActive != nil {
		fields["is_active"] = *req.IsActive
	}

	if len(fields) > 0 {
		if err := s.repo.UpdateDiscount(ctx, id, fields); err != nil {
			return nil, fmt.Errorf("update discount: %w", err)
		}
	}
	updated, err := s.repo.FindDiscount(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("update discount: reload: %w", err)
	}
	resp := toDiscountResponse(*updated)
	return &resp, nil
}

// ─── Settings ─────────────────────────────────────────────────────────────────

func (s *Service) GetSettings(ctx context.Context) (*BillingSettingsResponse, error) {
	st, err := s.settings(ctx)
	if err != nil {
		return nil, fmt.Errorf("get settings: %w", err)
	}
	tc := database.MustGetTenant(ctx)
	return &BillingSettingsResponse{
		GymID:            tc.GymID(),
		InvoicePrefix:    st.InvoicePrefix,
		GSTIN:            st.GSTIN,
		DefaultTaxRate:   st.DefaultTaxRate,
		DefaultSACCode:   st.DefaultSACCode,
		PricesIncludeTax: st.PricesIncludeTax,
		LegalName:        st.LegalName,
		AddressLine:      st.AddressLine,
		StateName:        st.StateName,
	}, nil
}

func (s *Service) UpdateSettings(ctx context.Context, req UpdateBillingSettingsRequest) (*BillingSettingsResponse, error) {
	fields := map[string]any{}
	if req.InvoicePrefix != nil {
		v := strings.TrimSpace(*req.InvoicePrefix)
		if v == "" {
			return nil, fmt.Errorf("invoice_prefix cannot be empty")
		}
		fields["invoice_prefix"] = v
	}
	if req.GSTIN != nil {
		fields["gstin"] = strings.TrimSpace(*req.GSTIN)
	}
	if req.DefaultTaxRate != nil {
		if *req.DefaultTaxRate < 0 || *req.DefaultTaxRate > 100 {
			return nil, fmt.Errorf("default_tax_rate must be between 0 and 100")
		}
		fields["default_tax_rate"] = *req.DefaultTaxRate
	}
	if req.DefaultSACCode != nil {
		fields["default_sac_code"] = strings.TrimSpace(*req.DefaultSACCode)
	}
	if req.PricesIncludeTax != nil {
		fields["prices_include_tax"] = *req.PricesIncludeTax
	}
	if req.LegalName != nil {
		fields["legal_name"] = strings.TrimSpace(*req.LegalName)
	}
	if req.AddressLine != nil {
		fields["address_line"] = strings.TrimSpace(*req.AddressLine)
	}
	if req.StateName != nil {
		fields["state_name"] = strings.TrimSpace(*req.StateName)
	}
	if len(fields) > 0 {
		if err := s.repo.UpsertSettings(ctx, fields); err != nil {
			return nil, fmt.Errorf("update settings: %w", err)
		}
	}
	return s.GetSettings(ctx)
}

// ─── mapping ──────────────────────────────────────────────────────────────────

func toInvoiceResponse(r invoiceRow, items []InvoiceItem) InvoiceResponse {
	itemResponses := make([]InvoiceItemResponse, 0, len(items))
	for _, it := range items {
		itemResponses = append(itemResponses, InvoiceItemResponse{
			ID: it.ID, Description: it.Description, ItemType: it.ItemType,
			ReferenceID: it.ReferenceID, Quantity: it.Quantity,
			UnitPriceInPaise:  it.UnitPriceInPaise,
			UnitPriceInRupees: paiseToRupees(it.UnitPriceInPaise),
			DiscountInPaise:   it.DiscountInPaise, TaxRatePct: it.TaxRatePct,
			SACCode: it.SACCode, TaxInPaise: it.TaxInPaise,
			LineTotalInPaise:  it.LineTotalInPaise,
			LineTotalInRupees: paiseToRupees(it.LineTotalInPaise),
		})
	}

	// Cancelled invoices owe nothing — they're void, not outstanding.
	due := r.TotalInPaise - r.PaidInPaise
	if due < 0 || r.Status == StatusCancelled {
		due = 0
	}

	return InvoiceResponse{
		ID: r.ID, MemberID: r.MemberID,
		MemberName:  strings.TrimSpace(r.MemberFirstName + " " + r.MemberLastName),
		MemberPhone: r.MemberPhone,
		InvoiceNumber: r.InvoiceNumber, FinancialYear: r.FinancialYear, Status: r.Status,
		PaymentState: derivePaymentState(r.TotalInPaise, r.PaidInPaise),
		PaidInPaise:  r.PaidInPaise, DueInPaise: due,
		InvoiceDate: r.InvoiceDate, DueDate: r.DueDate,
		PlaceOfSupply: r.PlaceOfSupply, GSTIN: r.GSTIN, PricesIncludeTax: r.PricesIncludeTax,
		DiscountCode: r.DiscountCode, DiscountLabel: r.DiscountLabel,
		DiscountReason: r.DiscountReason, DiscountInPaise: r.DiscountInPaise,
		SubtotalInPaise: r.SubtotalInPaise, TaxInPaise: r.TaxInPaise,
		TotalInPaise: r.TotalInPaise, TotalInRupees: paiseToRupees(r.TotalInPaise),
		// Intra-state split: half each. Derived for display only (FR-04 §3.2).
		CGSTInPaise: r.TaxInPaise / 2,
		SGSTInPaise: r.TaxInPaise - r.TaxInPaise/2,
		Notes:       r.Notes, CancelledReason: r.CancelledReason, CancelledAt: r.CancelledAt,
		CreatedAt: r.CreatedAt,
		Items:     itemResponses,
	}
}

func toSummaryResponse(r invoiceRow) InvoiceSummaryResponse {
	due := r.TotalInPaise - r.PaidInPaise
	if due < 0 || r.Status == StatusCancelled {
		due = 0
	}
	return InvoiceSummaryResponse{
		ID: r.ID, MemberID: r.MemberID,
		MemberName:    strings.TrimSpace(r.MemberFirstName + " " + r.MemberLastName),
		InvoiceNumber: r.InvoiceNumber, Status: r.Status,
		PaymentState: derivePaymentState(r.TotalInPaise, r.PaidInPaise),
		InvoiceDate:  r.InvoiceDate, DueDate: r.DueDate,
		TotalInPaise: r.TotalInPaise, TotalInRupees: paiseToRupees(r.TotalInPaise),
		PaidInPaise: r.PaidInPaise, DueInPaise: due,
		CreatedAt: r.CreatedAt,
	}
}

func toDiscountResponse(d Discount) DiscountResponse {
	return DiscountResponse{
		ID: d.ID, Code: d.Code, Name: d.Name, DiscountType: d.DiscountType,
		Value: d.Value, ValidFrom: d.ValidFrom, ValidUntil: d.ValidUntil,
		MaxUses: d.MaxUses, TimesUsed: d.TimesUsed, IsActive: d.IsActive,
		CreatedAt: d.CreatedAt,
	}
}

func optionalText(s string) *string {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	return &s
}

func today() time.Time {
	n := time.Now()
	return time.Date(n.Year(), n.Month(), n.Day(), 0, 0, 0, 0, time.UTC)
}
