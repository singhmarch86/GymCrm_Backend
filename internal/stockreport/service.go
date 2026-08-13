package stockreport

import (
	"context"
	"fmt"
	"math"

	"gymcrm/internal/staffwork"
)

type Service struct{ repo *Repository }

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

// Report builds the stock analytics for a window.
func (s *Service) Report(
	ctx context.Context, rng staffwork.Range, leadDays int,
) (*StockReport, error) {
	if leadDays <= 0 {
		leadDays = DefaultLeadDays
	}
	days := rng.Days()

	rows, err := s.repo.Products(ctx, rng.FromString(), rng.ToString())
	if err != nil {
		return nil, fmt.Errorf("stockreport: products: %w", err)
	}

	out := &StockReport{
		From:       rng.FromString(),
		To:         rng.ToString(),
		Days:       days,
		LeadDays:   leadDays,
		Products:   make([]ProductStock, 0, len(rows)),
		Categories: []CategoryTotal{},
	}

	byCategory := map[string]*CategoryTotal{}
	var categoryOrder []string

	for _, r := range rows {
		p := ProductStock{
			ProductID:         r.ProductID,
			Name:              r.Name,
			SKU:               r.SKU,
			Category:          r.Category,
			StockQty:          r.StockQty,
			ReorderLevel:      r.ReorderLevel,
			UnitsSold:         r.UnitsSold,
			RevenueInPaise:    r.RevenueInPaise,
			ProfitInPaise:     r.ProfitInPaise,
			StockValueInPaise: r.StockValueInPaise,
		}

		if r.RevenueInPaise > 0 {
			p.MarginPct = int(r.ProfitInPaise * 100 / r.RevenueInPaise)
		}

		p.PerDay = float64(r.UnitsSold) / float64(days)
		// Rounded to two places for display. The verdicts below use the raw
		// rate, so a rounded 0.00 never turns a slow seller into a dead one.
		p.PerDay = math.Round(p.PerDay*100) / 100

		rate := float64(r.UnitsSold) / float64(days)
		if rate > 0 {
			cover := int(float64(r.StockQty) / rate)
			p.DaysCover = &cover

			// What the level should be to survive a delivery, with a little
			// headroom. Advisory only — never written back, because a
			// suggestion that silently edits a threshold somebody set is a
			// change nobody agreed to.
			p.SuggestedReorder = int(math.Ceil(rate * float64(leadDays) * 1.5))
			if p.SuggestedReorder < 1 {
				p.SuggestedReorder = 1
			}
		}

		p.Verdict, p.Note = verdictFor(p, leadDays)

		if p.Verdict == VerdictDead {
			out.DeadCount++
			out.DeadValueInPaise += r.StockValueInPaise
		}
		// A mismatch is a reorder level that would fire at a moment that costs
		// money — not merely one that differs from the suggestion.
		//
		// The first version of this flagged any level more than 50% from the
		// suggestion and lit up all eleven products, which is the same as
		// flagging none: a level set cautiously is not an error, and a report
		// that disagrees with every threshold in the shop gets ignored by the
		// second week.
		//
		// So only two cases count. Firing later than a delivery takes means
		// running out while waiting for stock. Firing at several times the
		// needed level means holding capital for no reason.
		if rate > 0 && p.SuggestedReorder > 0 {
			coverAtReorder := float64(p.ReorderLevel) / rate
			switch {
			case coverAtReorder < float64(leadDays):
				out.MismatchCount++
			case p.ReorderLevel > p.SuggestedReorder*3:
				out.MismatchCount++
			}
		}

		out.UnitsSold += r.UnitsSold
		out.RevenueInPaise += r.RevenueInPaise
		out.ProfitInPaise += r.ProfitInPaise
		out.StockValueInPaise += r.StockValueInPaise

		cat := r.Category
		if cat == "" {
			cat = "Uncategorised"
		}
		if _, ok := byCategory[cat]; !ok {
			byCategory[cat] = &CategoryTotal{Category: cat}
			categoryOrder = append(categoryOrder, cat)
		}
		c := byCategory[cat]
		c.UnitsSold += r.UnitsSold
		c.RevenueInPaise += r.RevenueInPaise
		c.ProfitInPaise += r.ProfitInPaise

		out.Products = append(out.Products, p)
	}

	// Insertion order, not map order: Go randomises map iteration and the same
	// request would otherwise return the categories shuffled every time.
	for _, name := range categoryOrder {
		c := byCategory[name]
		if out.RevenueInPaise > 0 {
			c.SharePct = int(c.RevenueInPaise * 100 / out.RevenueInPaise)
		}
		out.Categories = append(out.Categories, *c)
	}

	return out, nil
}

// verdictFor decides what a product's position means, and says why.
//
// Order matters. Out of stock beats everything; a product with no stock and no
// sales is out of stock, not dead, because the reason it sold nothing may be
// that there was nothing to sell.
func verdictFor(p ProductStock, leadDays int) (string, string) {
	if p.StockQty <= 0 {
		return VerdictOutOfStock,
			"Nothing on the shelf. Anybody asking is being turned away."
	}

	if p.UnitsSold == 0 {
		return VerdictDead, fmt.Sprintf(
			"Not one sold in this window, with %s sitting in stock.",
			rupees(p.StockValueInPaise))
	}

	cover := *p.DaysCover

	if cover <= leadDays {
		return VerdictReorderNow, fmt.Sprintf(
			"About %d days left at the current rate, and a restock takes %d. "+
				"Order now or run out.", cover, leadDays)
	}

	if cover >= OverstockedDays {
		return VerdictOverstocked, fmt.Sprintf(
			"About %d days of cover — %s of stock that will take months to "+
				"sell.", cover, rupees(p.StockValueInPaise))
	}

	return VerdictHealthy, fmt.Sprintf("About %d days of cover.", cover)
}

func rupees(paise int64) string {
	return fmt.Sprintf("₹%d", paise/100)
}
