package queues

import "testing"

// At zero the gym is actively turning customers away; below the reorder level
// it merely might. The whole queue is built on that distinction.
func TestOutOfStockIsZeroOrBelow(t *testing.T) {
	cases := []struct {
		qty  int
		want bool
	}{
		{-1, true}, // a correction can push it negative; still empty
		{0, true},
		{1, false},
		{50, false},
	}
	for _, c := range cases {
		if got := (StockItem{StockQty: c.qty}).OutOfStock(); got != c.want {
			t.Fatalf("qty %d: OutOfStock() = %v, want %v", c.qty, got, c.want)
		}
	}
}

// A product whose reorder level is zero is flagged only when it is empty.
// Treating "0 <= 0" as low would put every never-configured product in the
// queue on day one, which is how a queue becomes wallpaper.
func TestZeroReorderLevelOnlyFlagsWhenEmpty(t *testing.T) {
	empty := StockItem{StockQty: 0, ReorderLevel: 0}
	if !empty.OutOfStock() {
		t.Fatal("an empty product is out of stock whatever its reorder level")
	}
	stocked := StockItem{StockQty: 5, ReorderLevel: 0}
	if stocked.OutOfStock() {
		t.Fatal("5 in hand is not out of stock")
	}
}

func TestGroupCountMatchesItems(t *testing.T) {
	g := StockGroup{Items: []StockItem{{}, {}, {}}}
	if g.Count() != 3 {
		t.Fatalf("Count() = %d, want 3", g.Count())
	}
	if (StockGroup{}).Count() != 0 {
		t.Fatal("an empty group counts zero, not nil")
	}
}
