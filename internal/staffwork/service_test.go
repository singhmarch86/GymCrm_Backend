package staffwork

import (
	"testing"
	"time"
)

func TestParseDayDefaultsToTodayInIST(t *testing.T) {
	got, err := ParseDay("")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	// The gym's today, not the server's. A server running UTC is 5h30m behind,
	// so between midnight and 05:30 IST the two disagree about the date — and
	// the whole screen would show yesterday.
	want := time.Now().In(IST).Format("2006-01-02")
	if got.Format("2006-01-02") != want {
		t.Fatalf("date = %s, want %s", got.Format("2006-01-02"), want)
	}
}

func TestParseDayRejectsGarbage(t *testing.T) {
	for _, in := range []string{"11-08-2026", "yesterday", "2026/08/11", "2026-13-45"} {
		if _, err := ParseDay(in); err == nil {
			t.Fatalf("ParseDay(%q) should have failed", in)
		}
	}
}

func TestParseDayIsInIST(t *testing.T) {
	d, err := ParseDay("2026-08-11")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if _, offset := d.Zone(); offset != 5*3600+30*60 {
		t.Fatalf("offset = %d, want IST (19800)", offset)
	}
}

func TestOnlyMoneyCategoriesCarryAmounts(t *testing.T) {
	// A ₹0 next to "At Risk handled" would read as a failure rather than as
	// "money is not the unit here".
	for _, c := range []Category{CatPayments, CatRenewals, CatSales, CatInvoices, CatWallet} {
		if !c.HasMoney() {
			t.Fatalf("%s should carry money", c)
		}
	}
	for _, c := range []Category{CatRetention, CatLeads, CatLifecycle} {
		if c.HasMoney() {
			t.Fatalf("%s must not carry money", c)
		}
	}
}

func TestEveryCategoryHasALabel(t *testing.T) {
	for _, c := range AllCategories {
		if got := c.Label(); got == "" || got == string(c) {
			t.Fatalf("category %q has no human label", c)
		}
	}
}

func TestCategoryValidationRejectsUnknown(t *testing.T) {
	if IsValidCategory("attendance") {
		t.Fatal("attendance is not a category — the table has no acting user")
	}
	if IsValidCategory("") || IsValidCategory("'; DROP TABLE payments; --") {
		t.Fatal("invalid category accepted")
	}
	for _, c := range AllCategories {
		if !IsValidCategory(string(c)) {
			t.Fatalf("%s should be valid", c)
		}
	}
}

// Display order must not depend on output, or the screen becomes a leaderboard
// (FR-13 §1, §9).
func TestCategoryRankIsFixed(t *testing.T) {
	if categoryRank(CatPayments) >= categoryRank(CatWallet) {
		t.Fatal("payments should sort before wallet")
	}
	if categoryRank("nonsense") != len(AllCategories) {
		t.Fatal("unknown categories should sort last, not first")
	}
}

func TestEarlierAndLaterIgnoreNils(t *testing.T) {
	a := time.Date(2026, 8, 11, 9, 0, 0, 0, IST)
	b := time.Date(2026, 8, 11, 21, 0, 0, 0, IST)

	if got := earlier(nil, &a); got == nil || !got.Equal(a) {
		t.Fatal("earlier(nil, a) should be a")
	}
	if got := earlier(&b, &a); !got.Equal(a) {
		t.Fatal("earlier should pick the earlier time")
	}
	if got := later(&a, &b); !got.Equal(b) {
		t.Fatal("later should pick the later time")
	}
	if got := later(&a, nil); !got.Equal(a) {
		t.Fatal("later(a, nil) should be a")
	}
}
