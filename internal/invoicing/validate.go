package invoicing

import (
	"fmt"
	"strings"
	"time"
)

func parseDate(s string) (*time.Time, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil, nil
	}
	t, err := time.Parse("2006-01-02", s)
	if err != nil {
		return nil, fmt.Errorf("invalid date %q: expected YYYY-MM-DD", s)
	}
	d := time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
	return &d, nil
}

var validItemTypes = map[string]bool{
	ItemTypePlan: true, ItemTypePTPackage: true, ItemTypeProduct: true, ItemTypeCustom: true,
}

func validateAddItem(req *AddItemRequest) error {
	if strings.TrimSpace(req.Description) == "" {
		return ErrDescriptionRequired
	}
	if req.Quantity == 0 {
		req.Quantity = 1 // sensible default rather than a rejection
	}
	if req.Quantity < 0 {
		return ErrQuantityInvalid
	}
	if req.UnitPriceInPaise < 0 {
		return ErrUnitPriceNegative
	}
	if req.DiscountInPaise < 0 {
		return ErrDiscountNegative
	}
	if req.ItemType == "" {
		req.ItemType = ItemTypeCustom
	}
	if !validItemTypes[req.ItemType] {
		return fmt.Errorf("item_type must be one of: plan, pt_package, product, custom")
	}
	if req.TaxRatePct != nil && (*req.TaxRatePct < 0 || *req.TaxRatePct > 100) {
		return fmt.Errorf("tax_rate_pct must be between 0 and 100")
	}
	return nil
}

func validateCreateDiscount(req CreateDiscountRequest) (validFrom, validUntil *time.Time, err error) {
	if strings.TrimSpace(req.Code) == "" {
		return nil, nil, ErrDiscountCodeMissing
	}
	if strings.TrimSpace(req.Name) == "" {
		return nil, nil, ErrDiscountNameMissing
	}
	if req.DiscountType != DiscountPercent && req.DiscountType != DiscountFlat {
		return nil, nil, fmt.Errorf("discount_type must be one of: percent, flat")
	}
	if req.Value < 0 {
		return nil, nil, ErrDiscountValueRange
	}
	if req.DiscountType == DiscountPercent && req.Value > 100 {
		return nil, nil, ErrDiscountValueRange
	}
	if req.MaxUses != nil && *req.MaxUses <= 0 {
		return nil, nil, fmt.Errorf("max_uses must be greater than 0 when provided")
	}
	if validFrom, err = parseDate(req.ValidFrom); err != nil {
		return nil, nil, err
	}
	if validUntil, err = parseDate(req.ValidUntil); err != nil {
		return nil, nil, err
	}
	if validFrom != nil && validUntil != nil && validUntil.Before(*validFrom) {
		return nil, nil, fmt.Errorf("valid_until cannot be before valid_from")
	}
	return validFrom, validUntil, nil
}

// checkDiscountUsable enforces the rules that must fail loudly rather than
// silently ignoring a discount staff believe they applied — FR-04 §4 rule 5.
func checkDiscountUsable(d *Discount, today time.Time) error {
	if !d.IsActive {
		return ErrDiscountInactive
	}
	if d.ValidFrom != nil && today.Before(*d.ValidFrom) {
		return ErrDiscountExpired
	}
	if d.ValidUntil != nil && today.After(*d.ValidUntil) {
		return ErrDiscountExpired
	}
	if d.MaxUses != nil && d.TimesUsed >= *d.MaxUses {
		return ErrDiscountExhausted
	}
	return nil
}

func validateCancel(req CancelInvoiceRequest) error {
	if strings.TrimSpace(req.Reason) == "" {
		return ErrCancelReasonMissing
	}
	return nil
}
