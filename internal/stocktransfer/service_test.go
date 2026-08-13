package stocktransfer

import "testing"

func TestIsSurplus(t *testing.T) {
	cases := []struct {
		name    string
		stock   int
		reorder int
		sold    int
		want    bool
		why     string
	}{
		{"empty shelf is never surplus", 0, 0, 0, false,
			"nothing to send"},
		{"at reorder level is a shortage, not a surplus", 3, 3, 0, false,
			"a product at its reorder level has a supply problem whatever its sales look like"},
		{"below reorder level", 1, 3, 50, false,
			"selling well and nearly out is the opposite of surplus"},
		{"dead stock above reorder", 10, 3, 0, true,
			"nothing sold in the window and more than the reorder level on the shelf"},
		{"fast mover with deep stock is fine", 40, 3, 200, false,
			"40 units at 200 per 60 days is 12 days of cover"},
		{"slow mover with deep stock is surplus", 40, 3, 5, true,
			"40 units at 5 per 60 days is 480 days of cover"},
		{"exactly at the threshold is not over it", 90, 3, 60, false,
			"90 units at 60 per 60 days is exactly 90 days of cover, and the test is strict"},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := isSurplus(c.stock, c.reorder, c.sold)
			if got != c.want {
				t.Errorf("isSurplus(stock=%d, reorder=%d, sold=%d) = %v, want %v — %s",
					c.stock, c.reorder, c.sold, got, c.want, c.why)
			}
		})
	}
}

func TestMatchKey(t *testing.T) {
	sku := func(s string) *string { return &s }

	t.Run("sku wins when present", func(t *testing.T) {
		k, by := matchKey(sku("WHY-1KG"), "Whey Protein 1kg")
		if by != "sku" {
			t.Fatalf("matched by %q, want sku", by)
		}
		if k != "sku:why-1kg" {
			t.Fatalf("key %q, want sku:why-1kg", k)
		}
	})

	t.Run("same sku in different case is the same item", func(t *testing.T) {
		a, _ := matchKey(sku("WHY-1KG"), "Whey Protein 1kg")
		b, _ := matchKey(sku(" why-1kg "), "Whey protein, 1 kg")
		if a != b {
			t.Errorf("%q != %q — a SKU typed in a different case at another "+
				"branch must not split the item in two", a, b)
		}
	})

	t.Run("falls back to name", func(t *testing.T) {
		k, by := matchKey(nil, "Gym Towel")
		if by != "name" || k != "name:gym towel" {
			t.Fatalf("got (%q, %q), want (name:gym towel, name)", k, by)
		}
	})

	t.Run("blank sku is not a sku", func(t *testing.T) {
		_, by := matchKey(sku("   "), "Gym Towel")
		if by != "name" {
			t.Errorf("matched by %q, want name — whitespace is not an identifier", by)
		}
	})

	t.Run("different names stay different items", func(t *testing.T) {
		a, _ := matchKey(nil, "Gym Towel")
		b, _ := matchKey(nil, "Gym Towel Large")
		if a == b {
			t.Error("two differently named products collapsed into one item")
		}
	})
}
