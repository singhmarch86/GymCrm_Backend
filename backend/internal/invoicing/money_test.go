package invoicing

import (
	"testing"
	"time"
)

func TestLineAmounts_TaxExclusive(t *testing.T) {
	tests := []struct {
		name                                       string
		unitPaise                                  int64
		qty                                        int
		discount                                   int64
		rate                                       float64
		wantGross, wantTaxable, wantTax, wantTotal int64
	}{
		{
			// ₹12,000 @ 18% → ₹2,160 tax → ₹14,160
			name: "plain 18 percent", unitPaise: 1200000, qty: 1, rate: 18,
			wantGross: 1200000, wantTaxable: 1200000, wantTax: 216000, wantTotal: 1416000,
		},
		{
			name: "quantity multiplies before tax", unitPaise: 50000, qty: 3, rate: 18,
			wantGross: 150000, wantTaxable: 150000, wantTax: 27000, wantTotal: 177000,
		},
		{
			// Discount must reduce the taxable base, not the post-tax total.
			name: "discount is applied before tax", unitPaise: 1200000, qty: 1, discount: 200000, rate: 18,
			wantGross: 1200000, wantTaxable: 1000000, wantTax: 180000, wantTotal: 1180000,
		},
		{
			// A discount larger than the line clamps to zero, never negative.
			name: "discount clamped to gross", unitPaise: 100000, qty: 1, discount: 500000, rate: 18,
			wantGross: 100000, wantTaxable: 0, wantTax: 0, wantTotal: 0,
		},
		{
			name: "zero tax rate", unitPaise: 100000, qty: 1, rate: 0,
			wantGross: 100000, wantTaxable: 100000, wantTax: 0, wantTotal: 100000,
		},
		{
			// 999 paise @ 18% = 179.82 → rounds half-up to 180.
			name: "rounds half up", unitPaise: 999, qty: 1, rate: 18,
			wantGross: 999, wantTaxable: 999, wantTax: 180, wantTotal: 1179,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			gross, taxable, tax, total := lineAmounts(tc.unitPaise, tc.qty, tc.discount, tc.rate, false)
			if gross != tc.wantGross {
				t.Errorf("gross = %d, want %d", gross, tc.wantGross)
			}
			if taxable != tc.wantTaxable {
				t.Errorf("taxable = %d, want %d", taxable, tc.wantTaxable)
			}
			if tax != tc.wantTax {
				t.Errorf("tax = %d, want %d", tax, tc.wantTax)
			}
			if total != tc.wantTotal {
				t.Errorf("total = %d, want %d", total, tc.wantTotal)
			}
			// The invariant that must hold no matter what: the parts add up.
			if taxable+tax != total {
				t.Errorf("taxable(%d) + tax(%d) != total(%d)", taxable, tax, total)
			}
		})
	}
}

func TestLineAmounts_TaxInclusive(t *testing.T) {
	// ₹14,160 inclusive of 18% → base ₹12,000, tax ₹2,160. The member pays the
	// advertised price exactly; the tax is carved out of it, not added to it.
	_, taxable, tax, total := lineAmounts(1416000, 1, 0, 18, true)

	if total != 1416000 {
		t.Errorf("inclusive total = %d, want 1416000 (price must not change)", total)
	}
	if tax != 216000 {
		t.Errorf("inclusive tax = %d, want 216000", tax)
	}
	if taxable != 1200000 {
		t.Errorf("inclusive base = %d, want 1200000", taxable)
	}
	if taxable+tax != total {
		t.Errorf("base(%d) + tax(%d) != total(%d)", taxable, tax, total)
	}
}

func TestResolveDiscount(t *testing.T) {
	pct := &Discount{DiscountType: DiscountPercent, Value: 25}
	if got := resolveDiscount(pct, 1200000); got != 300000 {
		t.Errorf("25%% of 1200000 = %d, want 300000", got)
	}

	flat := &Discount{DiscountType: DiscountFlat, Value: 50000}
	if got := resolveDiscount(flat, 1200000); got != 50000 {
		t.Errorf("flat = %d, want 50000", got)
	}

	// Never more than the base it applies to.
	big := &Discount{DiscountType: DiscountFlat, Value: 9999999}
	if got := resolveDiscount(big, 100000); got != 100000 {
		t.Errorf("oversized flat = %d, want clamp to 100000", got)
	}

	if got := resolveDiscount(nil, 100000); got != 0 {
		t.Errorf("nil discount = %d, want 0", got)
	}
}

func TestFinancialYear(t *testing.T) {
	tests := []struct {
		date string
		want string
	}{
		{"2026-04-01", "2026-27"}, // first day of FY
		{"2026-08-08", "2026-27"},
		{"2027-03-31", "2026-27"}, // last day of FY
		{"2027-04-01", "2027-28"}, // rolls over
		{"2026-01-15", "2025-26"}, // January belongs to the previous FY
	}
	for _, tc := range tests {
		d, err := time.Parse("2006-01-02", tc.date)
		if err != nil {
			t.Fatal(err)
		}
		if got := financialYear(d); got != tc.want {
			t.Errorf("financialYear(%s) = %s, want %s", tc.date, got, tc.want)
		}
	}
}

func TestDerivePaymentState(t *testing.T) {
	tests := []struct {
		total, paid int64
		want        string
	}{
		{1416000, 0, PaymentStateUnpaid},
		{1416000, 500000, PaymentStatePartial},
		{1416000, 1416000, PaymentStatePaid},
		{1416000, 2000000, PaymentStatePaid}, // overpayment still reads as paid
		{0, 0, PaymentStateUnpaid},
	}
	for _, tc := range tests {
		if got := derivePaymentState(tc.total, tc.paid); got != tc.want {
			t.Errorf("derivePaymentState(%d, %d) = %s, want %s", tc.total, tc.paid, got, tc.want)
		}
	}
}
