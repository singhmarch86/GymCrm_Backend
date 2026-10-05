package devseed

import "fmt"

// The shop: products, stock and counter sales.
//
// Stock levels are set so the low-stock queue has something to show without
// the shelf looking abandoned — three items under their reorder level out of
// eleven, which is a normal Tuesday rather than a crisis.
//
// Every level is reached through stock_movements rather than written straight
// onto products.stock_qty. The movements ledger is the single writer of stock
// (FR-07 §1), and a seed that set the column directly would produce a gym
// whose history does not explain its present — the first thing anybody
// checking the stock report would notice.

type seedProduct struct {
	id       int64
	name     string
	price    int64
	cost     int64
	qty      int
	reorder  int
	category string
}

func (s *seeder) seedProducts() error {
	defs := []struct {
		name, sku, category    string
		price, cost            int64
		opening, reorder, sold int
	}{
		{"Whey Protein 1kg", "SUP-WHEY-1K", "Supplements", 320000, 240000, 24, 6, 9},
		{"Mass Gainer 1kg", "SUP-GAIN-1K", "Supplements", 280000, 210000, 12, 4, 3},
		{"Pre-workout 300g", "SUP-PRE-300", "Supplements", 180000, 130000, 10, 4, 7},
		{"Creatine 250g", "SUP-CRE-250", "Supplements", 140000, 95000, 8, 3, 2},
		{"Protein Bar", "SNK-BAR", "Snacks", 12000, 7000, 120, 30, 74},
		{"Energy Drink 500ml", "SNK-ENR-500", "Snacks", 6000, 3500, 96, 24, 61},
		{"Mineral Water 1L", "SNK-WAT-1L", "Snacks", 2000, 1000, 200, 48, 143},
		{"Gym Gloves", "ACC-GLOVE", "Accessories", 45000, 28000, 18, 5, 6},
		{"Shaker Bottle", "ACC-SHAKE", "Accessories", 25000, 14000, 30, 8, 19},
		{"Resistance Band", "ACC-BAND", "Accessories", 35000, 20000, 14, 5, 4},
		{"Gym Towel", "ACC-TOWEL", "Accessories", 18000, 9000, 25, 6, 8},
	}

	for _, d := range defs {
		var id int64
		err := s.tx.Raw(`
			INSERT INTO products
			    (gym_id, sku, name, category, price_in_paise, cost_in_paise,
			     stock_qty, reorder_level, is_active)
			VALUES (?, ?, ?, ?, ?, ?, 0, ?, true)
			RETURNING id`,
			s.gymID, d.sku, d.name, d.category, d.price, d.cost,
			d.reorder).Scan(&id).Error
		if err != nil {
			return err
		}

		// Opening stock arrives as a purchase, sixty days back.
		if err := s.stockMove(id, "purchase", d.opening, d.opening,
			"Opening stock", -60); err != nil {
			return err
		}

		s.products = append(s.products, seedProduct{
			id: id, name: d.name, price: d.price, cost: d.cost,
			qty: d.opening, reorder: d.reorder, category: d.category,
		})
		s.productCount++
	}
	return nil
}

// stockMove writes one movement and sets the resulting level, so the ledger
// and the column can never disagree.
func (s *seeder) stockMove(
	productID int64, kind string, qty, after int, reason string, daysAgo int,
) error {
	at := s.now.AddDate(0, 0, daysAgo)

	if err := s.tx.Exec(`
		INSERT INTO stock_movements
		    (gym_id, product_id, movement_type, quantity, qty_after, reason,
		     created_by_user_id, created_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		s.gymID, productID, kind, qty, after, reason,
		s.ownerUserID, at).Error; err != nil {
		return err
	}
	return s.tx.Exec(`UPDATE products SET stock_qty = ? WHERE id = ?`,
		after, productID).Error
}

// seedSales rings up counter sales over the last eight weeks, drawing stock
// down through the same ledger a real sale uses.
func (s *seeder) seedSales() error {
	if len(s.products) == 0 {
		return nil
	}

	saleNo := 1
	for i := range s.products {
		p := &s.products[i]

		// How many of this product went over the window, spread across
		// several separate sales rather than one big one.
		remaining := s.soldQtyFor(p.name)
		for remaining > 0 {
			qty := 1 + s.rng.Intn(3)
			if qty > remaining {
				qty = remaining
			}
			remaining -= qty

			daysAgo := 1 + s.rng.Intn(55)
			at := s.now.AddDate(0, 0, -daysAgo)

			line := p.price * int64(qty)
			tax := line * 18 / 118 // prices are tax-inclusive at this gym
			var member *int64
			// Roughly two in three sales are attached to a member; the rest
			// are walk-ins, which is what a counter actually looks like.
			if s.rng.Intn(3) != 0 && len(s.members) > 0 {
				m := s.members[s.rng.Intn(len(s.members))].ID
				member = &m
			}

			var saleID int64
			err := s.tx.Raw(`
				INSERT INTO sales
				    (gym_id, member_id, sale_number, subtotal_in_paise,
				     tax_in_paise, discount_in_paise, total_in_paise,
				     payment_mode, is_refund, created_by_user_id, created_at)
				VALUES (?, ?, ?, ?, ?, 0, ?, ?, false, ?, ?)
				RETURNING id`,
				s.gymID, member, fmt.Sprintf("S-%04d", saleNo),
				line-tax, tax, line,
				pick(s.rng, []string{"cash", "upi", "upi", "debit_card"}),
				s.ownerUserID, at).Scan(&saleID).Error
			if err != nil {
				return err
			}
			saleNo++
			s.saleCount++

			if err := s.tx.Exec(`
				INSERT INTO sale_items
				    (gym_id, sale_id, product_id, product_name,
				     unit_price_in_paise, cost_in_paise, tax_rate_pct,
				     quantity, line_total_in_paise, created_at)
				VALUES (?, ?, ?, ?, ?, ?, 18.00, ?, ?, ?)`,
				s.gymID, saleID, p.id, p.name, p.price, p.cost,
				qty, line, at).Error; err != nil {
				return err
			}

			p.qty -= qty
			if err := s.stockMove(p.id, "sale", -qty, p.qty,
				"Counter sale", -daysAgo); err != nil {
				return err
			}
		}
	}
	return nil
}

// soldQtyFor keeps the sold quantities with the product definitions above, so
// the resulting shelf is a deliberate arrangement rather than whatever random
// draws happened to leave behind. Three items end below their reorder level.
func (s *seeder) soldQtyFor(name string) int {
	switch name {
	case "Whey Protein 1kg":
		return 9
	case "Mass Gainer 1kg":
		return 3
	case "Pre-workout 300g":
		return 7 // ends at 3, below its reorder level of 4
	case "Creatine 250g":
		return 2
	case "Protein Bar":
		return 74
	case "Energy Drink 500ml":
		return 61
	case "Mineral Water 1L":
		return 143 // ends at 57, comfortably above 48
	case "Gym Gloves":
		return 14 // ends at 4, below 5
	case "Shaker Bottle":
		return 19
	case "Resistance Band":
		return 10 // ends at 4, below 5
	case "Gym Towel":
		return 8
	}
	return 0
}
