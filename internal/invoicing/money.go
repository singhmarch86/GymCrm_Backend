package invoicing

import (
	"math"
	"time"
)

// Money arithmetic for invoices. See FR-04 §3.1.
//
// Everything here is int64 paise. No float ever holds an amount — floats are
// used only to carry a tax *rate* (18.00), and the single multiplication that
// touches one is immediately rounded back to an integer.
//
// The ordering below is deliberate and must not be rearranged:
//
//	gross      = unit_price × quantity
//	taxable    = gross − discount
//	tax        = round_half_up(taxable × rate / 100)
//	line_total = taxable + tax
//
// Rounding happens once per line, at the tax step. Rounding twice, or taxing
// an invoice total when lines carry different rates, produces totals that are
// off by a paise or two — which is exactly the kind of error an accountant
// notices and nobody can explain a year later.

// roundHalfUp rounds to the nearest integer paise, halves away from zero.
// math.Round already rounds half away from zero, which is what Indian invoice
// convention expects; this wrapper exists so the intent is stated once and the
// rest of the file reads declaratively.
func roundHalfUp(v float64) int64 {
	return int64(math.Round(v))
}

// lineAmounts computes the derived amounts for a single line.
//
// discount is clamped to gross: a discount may reduce a line to zero but must
// never make it negative (FR-04 §4 rule 3).
func lineAmounts(unitPriceInPaise int64, quantity int, discountInPaise int64, taxRatePct float64, pricesIncludeTax bool) (gross, taxable, tax, lineTotal int64) {
	gross = unitPriceInPaise * int64(quantity)

	if discountInPaise > gross {
		discountInPaise = gross
	}
	taxable = gross - discountInPaise

	if pricesIncludeTax {
		// The listed price already contains the tax, so back it out rather
		// than adding on top:  tax = taxable − (taxable / (1 + rate/100)).
		// FR-04 open question 5.3 — this branch is inert until a gym opts in.
		base := float64(taxable) / (1 + taxRatePct/100)
		tax = taxable - roundHalfUp(base)
		lineTotal = taxable
		return gross, taxable - tax, tax, lineTotal
	}

	tax = roundHalfUp(float64(taxable) * taxRatePct / 100)
	lineTotal = taxable + tax
	return gross, taxable, tax, lineTotal
}

// resolveDiscount converts a discount rule into a concrete paise value against
// a given base amount. Percentages are resolved at application time and it is
// the resolved value that gets stored — the rule may change later, the
// document may not (FR-04 §4 rule 2).
func resolveDiscount(d *Discount, baseInPaise int64) int64 {
	if d == nil {
		return 0
	}
	var v int64
	switch d.DiscountType {
	case DiscountPercent:
		v = roundHalfUp(float64(baseInPaise) * d.Value / 100)
	case DiscountFlat:
		// Flat discounts are already stored in paise.
		v = int64(d.Value)
	}
	if v > baseInPaise {
		v = baseInPaise
	}
	if v < 0 {
		v = 0
	}
	return v
}

// financialYear returns the Indian FY label for a date: 1 April – 31 March.
// 15 Mar 2027 → "2026-27";  2 Apr 2026 → "2026-27".
func financialYear(t time.Time) string {
	y := t.Year()
	if int(t.Month()) < 4 {
		y--
	}
	return itoa4(y) + "-" + itoa2((y+1)%100)
}

func itoa4(v int) string {
	buf := []byte{'0' + byte(v/1000%10), '0' + byte(v/100%10), '0' + byte(v/10%10), '0' + byte(v%10)}
	return string(buf)
}

func itoa2(v int) string {
	return string([]byte{'0' + byte(v/10%10), '0' + byte(v%10)})
}

// paiseToRupees is display-only. Never use for storage or calculation.
func paiseToRupees(p int64) float64 { return float64(p) / 100 }

// derivePaymentState computes unpaid/partial/paid from money actually
// received. Deliberately not stored — a status column can silently disagree
// with the payments behind it; a computed one cannot (FR-04 §2).
func derivePaymentState(totalInPaise, paidInPaise int64) string {
	switch {
	case paidInPaise <= 0:
		return PaymentStateUnpaid
	case paidInPaise >= totalInPaise:
		return PaymentStatePaid
	default:
		return PaymentStatePartial
	}
}
