package queues

import (
	"context"
	"math"
	"time"
)

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// Stock builds the low-stock queue (FR-19 §5).
//
// The smallest queue in the package and the one that most clearly passes the
// test in §1: it reaches zero the moment somebody restocks, and zero means the
// gym is not turning customers away.
func (s *Service) Stock(ctx context.Context) (*StockQueue, error) {
	rows, err := s.repo.LowStock(ctx)
	if err != nil {
		return nil, err
	}
	total, err := s.repo.ProductCount(ctx)
	if err != nil {
		return nil, err
	}

	out := StockGroup{
		Key:      GroupOutOfStock,
		Label:    "Out of stock",
		Note:     "Nothing on the shelf. Every customer who asks for these is being turned away.",
		Severity: "urgent",
		Items:    []StockItem{},
	}
	low := StockGroup{
		Key:      GroupLow,
		Label:    "Running low",
		Note:     "At or below the reorder level. Still sellable, but not for long.",
		Severity: "warn",
		Items:    []StockItem{},
	}

	now := time.Now().In(IST)

	for _, r := range rows {
		item := StockItem{
			ProductID:       r.ProductID,
			Name:            r.Name,
			SKU:             r.SKU,
			Category:        r.Category,
			StockQty:        r.StockQty,
			ReorderLevel:    r.ReorderLevel,
			PriceInPaise:    r.PriceInPaise,
			SoldLast30:      r.SoldLast30,
			LastRestockedAt: r.LastRestockedAt,
		}

		if item.OutOfStock() {
			// Only meaningful for a product actually at zero. Attaching it to
			// a low-but-stocked row would be a countdown that has not started.
			//
			// Guarded on the restock date too: a product that went to zero in
			// June and was refilled in July is not "60 days out of stock", it
			// is low again for a new reason.
			if r.ZeroSince != nil &&
				(r.LastRestockedAt == nil || r.LastRestockedAt.Before(*r.ZeroSince)) {
				days := int(math.Floor(now.Sub(*r.ZeroSince).Hours() / 24))
				if days < 0 {
					days = 0
				}
				item.DaysOutOfStock = &days
			}
			out.Items = append(out.Items, item)
			continue
		}
		low.Items = append(low.Items, item)
	}

	// Both groups always returned, empty or not. "0 out of stock" is the most
	// useful sentence this screen can say.
	return &StockQueue{
		Groups:          []StockGroup{out, low},
		TotalProducts:   total,
		TotalFlagged:    len(rows),
		TotalOutOfStock: len(out.Items),
	}, nil
}
