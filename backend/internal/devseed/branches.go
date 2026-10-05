package devseed

// A second branch, so the chain views have two of something to compare.
//
// Seeded deliberately thin: a shop, and nothing else. Model Town has no
// members, no attendance and no leads, and that is the honest shape of a
// branch that just opened rather than an oversight. Giving it a full member
// base would double every other seeded number and make the single-branch
// screens — which is most of them — harder to read, for no gain.
//
// What it does have is stock, arranged so the cross-branch views have
// something to say: items short here and deep at the main branch, items the
// main branch is low on that this one still holds, and one item Model Town
// carries that Sarabha Nagar does not.

const (
	// The main gym gets a branch name here rather than at creation, because
	// it is not a branch until there are two of them. A gym that will only
	// ever have one location should never see branch labelling at all.
	mainBranchName   = "Sarabha Nagar"
	secondBranchName = "Model Town"

	// Distinct from both seeded users' phones — gyms.phone is uniquely
	// indexed, and the receptionist already holds 9876500002.
	secondBranchPhone = "9876500003"
)

func (s *seeder) seedSecondBranch() error {
	// One organization over both. Without it the transfer guard refuses
	// every move: a branch with a null organization_id is, correctly, not
	// part of any chain.
	var orgID int64
	if err := s.tx.Raw(`
		INSERT INTO organizations (name) VALUES (?) RETURNING id`,
		"Demo Fitness Group").Scan(&orgID).Error; err != nil {
		return err
	}
	s.orgID = orgID

	if err := s.tx.Exec(`
		UPDATE gyms SET organization_id = ?, branch_name = ?, updated_at = now()
		WHERE id = ?`, orgID, mainBranchName, s.gymID).Error; err != nil {
		return err
	}

	var branchID int64
	if err := s.tx.Raw(`
		INSERT INTO gyms
		    (name, owner_name, phone, email, address, city, state, status,
		     organization_id, branch_name)
		VALUES (?, ?, ?, ?, ?, ?, ?, 'active', ?, ?)
		RETURNING id`,
		"Demo Fitness Gym", "Amanpreet Singh", secondBranchPhone,
		"modeltown@demofitnessgym.dev", "Shop 7, Model Town Market",
		"Ludhiana", "Punjab", orgID, secondBranchName,
	).Scan(&branchID).Error; err != nil {
		return err
	}
	s.branchGymID = branchID

	// The owner holds both branches; the receptionist holds only the one she
	// works at. That asymmetry is the point of the access table — a chain
	// view that showed every branch to everybody would make the grants
	// decorative.
	grants := []struct {
		userID int64
		gymID  int64
		role   string
	}{
		{s.ownerUserID, s.gymID, "owner"},
		{s.ownerUserID, branchID, "owner"},
		{s.staffUserID, s.gymID, "staff"},
	}
	for _, g := range grants {
		if err := s.tx.Exec(`
			INSERT INTO user_gym_access (user_id, gym_id, role)
			VALUES (?, ?, ?) ON CONFLICT DO NOTHING`,
			g.userID, g.gymID, g.role).Error; err != nil {
			return err
		}
	}

	if err := s.seedBranchStock(); err != nil {
		return err
	}
	return s.seedOpeningTransfer()
}

// seedBranchStock stocks Model Town.
//
// SKUs are shared with the main branch on purpose: matching across branches
// is by SKU, and a second branch whose products only matched by name would
// exercise the weaker path and hide the stronger one.
func (s *seeder) seedBranchStock() error {
	defs := []struct {
		name, sku, category string
		price, cost         int64
		opening, reorder    int
	}{
		// Short here, deep at the main branch — these are what the Move tab
		// exists to surface.
		{"Whey Protein 1kg", "SUP-WHEY-1K", "Supplements", 320000, 240000, 2, 6},
		{"Gym Towel", "ACC-TOWEL", "Accessories", 18000, 9000, 1, 6},
		{"Protein Bar", "SNK-BAR", "Snacks", 12000, 7000, 8, 30},

		// The other direction: Model Town is fine on these, and the main
		// branch is the one running low. A view that only ever pointed one
		// way would read as a hierarchy rather than a chain.
		{"Pre-workout 300g", "SUP-PRE-300", "Supplements", 180000, 130000, 22, 4},
		{"Gym Gloves", "ACC-GLOVE", "Accessories", 45000, 28000, 16, 5},

		// Comfortable at both.
		{"Mineral Water 1L", "SNK-WAT-1L", "Snacks", 2000, 1000, 90, 48},
		{"Shaker Bottle", "ACC-SHAKE", "Accessories", 25000, 14000, 20, 8},

		// Only sold here. Shows as "—" rather than 0 in the main branch's
		// column: not stocked and stocked-but-empty are different facts.
		{"Skipping Rope", "ACC-ROPE", "Accessories", 22000, 12000, 15, 5},
	}

	for _, d := range defs {
		var id int64
		if err := s.tx.Raw(`
			INSERT INTO products
			    (gym_id, sku, name, category, price_in_paise, cost_in_paise,
			     stock_qty, reorder_level, is_active)
			VALUES (?, ?, ?, ?, ?, ?, 0, ?, true)
			RETURNING id`,
			s.branchGymID, d.sku, d.name, d.category, d.price, d.cost,
			d.reorder).Scan(&id).Error; err != nil {
			return err
		}

		// Through the ledger, like every other level in the seed. Stock that
		// appeared without a movement would be the first thing to look wrong
		// on the very screen this branch exists to demonstrate.
		if err := s.branchStockMove(id, "purchase", d.opening, d.opening,
			"Opening stock", -45); err != nil {
			return err
		}
		s.productCount++
	}
	return nil
}

// branchStockMove is stockMove for the second branch. Separate rather than
// parameterised because stockMove is called from the sales seeder in a loop
// and threading a gym id through every call site would be noise at ten
// places to serve one.
func (s *seeder) branchStockMove(
	productID int64, kind string, qty, after int, reason string, daysAgo int,
) error {
	at := s.now.AddDate(0, 0, daysAgo)

	if err := s.tx.Exec(`
		INSERT INTO stock_movements
		    (gym_id, product_id, movement_type, quantity, qty_after, reason,
		     created_by_user_id, created_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		s.branchGymID, productID, kind, qty, after, reason,
		s.ownerUserID, at).Error; err != nil {
		return err
	}
	return s.tx.Exec(`
		UPDATE products SET stock_qty = ?, updated_at = ? WHERE id = ?`,
		after, at, productID).Error
}

// seedOpeningTransfer puts one completed transfer in the ledger.
//
// An empty Sent tab is a correct but useless first impression — it cannot
// show what a transfer looks like once made, and that is the thing somebody
// opening the screen wants to understand. Written as the real endpoint
// writes it: a header plus both movements, levels moved on both sides.
func (s *seeder) seedOpeningTransfer() error {
	const (
		sku = "SNK-ENR-500" // Energy Drink; the main branch is deep on these
		qty = 24
	)

	var src struct {
		ID       int64
		StockQty int
		Cost     int64
	}
	if err := s.tx.Raw(`
		SELECT id, stock_qty, cost_in_paise AS cost FROM products
		WHERE gym_id = ? AND sku = ? AND deleted_at IS NULL`,
		s.gymID, sku).Scan(&src).Error; err != nil {
		return err
	}
	// Defensive: if the shop seeder's catalogue ever changes underneath this,
	// skip rather than fail the whole seed over demo garnish.
	if src.ID == 0 || src.StockQty < qty {
		return nil
	}

	// Model Town does not carry it yet, so the transfer creates the row —
	// the same path the endpoint takes on first receipt, copying price and
	// cost from the sender.
	var dstID int64
	if err := s.tx.Raw(`
		INSERT INTO products
		    (gym_id, sku, name, category, price_in_paise, cost_in_paise,
		     stock_qty, reorder_level, is_active)
		SELECT ?, sku, name, category, price_in_paise, cost_in_paise, 0,
		       reorder_level, true
		FROM products WHERE id = ?
		RETURNING id`, s.branchGymID, src.ID).Scan(&dstID).Error; err != nil {
		return err
	}
	s.productCount++

	var transferID int64
	if err := s.tx.Raw(`
		INSERT INTO stock_transfers
		    (from_gym_id, to_gym_id, from_product_id, to_product_id, quantity,
		     unit_cost_in_paise, value_in_paise, reason, created_by_user_id,
		     created_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		RETURNING id`,
		s.gymID, s.branchGymID, src.ID, dstID, qty,
		src.Cost, src.Cost*int64(qty), "Stocking the new branch",
		s.ownerUserID, s.now.AddDate(0, 0, -40),
	).Scan(&transferID).Error; err != nil {
		return err
	}

	srcAfter := src.StockQty - qty
	if err := s.transferMove(s.gymID, src.ID, "transfer_out", -qty, srcAfter,
		transferID, -40); err != nil {
		return err
	}
	if err := s.transferMove(s.branchGymID, dstID, "transfer_in", qty, qty,
		transferID, -40); err != nil {
		return err
	}
	s.transferCount++
	return nil
}

func (s *seeder) transferMove(
	gymID, productID int64, kind string, qty, after int,
	transferID int64, daysAgo int,
) error {
	at := s.now.AddDate(0, 0, daysAgo)

	if err := s.tx.Exec(`
		INSERT INTO stock_movements
		    (gym_id, product_id, movement_type, quantity, qty_after, reason,
		     transfer_id, created_by_user_id, created_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		gymID, productID, kind, qty, after, "Stocking the new branch",
		transferID, s.ownerUserID, at).Error; err != nil {
		return err
	}
	return s.tx.Exec(`
		UPDATE products SET stock_qty = ?, updated_at = ? WHERE id = ?`,
		after, at, productID).Error
}
