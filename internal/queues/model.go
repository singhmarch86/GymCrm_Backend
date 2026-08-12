// Package queues answers a different question from the rest of the system:
// not "what happened" but "what is still owed".
//
// Everything else reports. Staff work reads eight append-only ledgers and
// tells you what already occurred; nothing on it can be acted on. The lead
// workflow was the first screen that named outstanding decisions and gave you
// the button, and it was the only one that changed how the gym worked.
//
// See docs/FR-19-money-and-stock-queues.md. The rule that governs every queue
// in this package: a gym must be able to drive it to zero, and zero must mean
// something good happened. A queue that cannot reach zero is a report wearing
// a queue's clothes, and within two weeks nobody reads it.
package queues

import "time"

// StockGroup is one band of the stock queue, worst first.
//
// Groups are returned even when empty. "0 out of stock" is the most useful
// sentence a queue can say, and a heading that vanishes at zero denies the
// reader that — they cannot tell "nothing is wrong" from "the section did not
// load".
type StockGroup struct {
	Key   string `json:"key"`
	Label string `json:"label"`

	// Why this group exists, in the reader's words. Shown under the heading.
	Note string `json:"note"`

	// Severity drives colour only. Deliberately not a number to rank by.
	Severity string `json:"severity"` // urgent | warn | normal

	Items []StockItem `json:"items"`
}

func (g StockGroup) Count() int { return len(g.Items) }

// StockItem is one product that needs attention.
type StockItem struct {
	ProductID int64   `json:"product_id"`
	Name      string  `json:"name"`
	SKU       *string `json:"sku,omitempty"`
	Category  *string `json:"category,omitempty"`

	StockQty     int `json:"stock_qty"`
	ReorderLevel int `json:"reorder_level"`

	PriceInPaise int64 `json:"price_in_paise"`

	// Units sold in the last 30 days. The whole point of the row: two left is
	// fine for something that sells twice a year and an emergency for
	// something that sells daily. Without it the reader has to guess.
	SoldLast30 int `json:"sold_last_30"`

	// When somebody last put stock in. Null if never — a product created with
	// an opening quantity and never touched since.
	LastRestockedAt *time.Time `json:"last_restocked_at,omitempty"`

	// How long it has been at zero. Only set for out-of-stock rows, because
	// for anything else it is not a fact — it is a countdown that has not
	// started.
	DaysOutOfStock *int `json:"days_out_of_stock,omitempty"`
}

// OutOfStock is the distinction the queue is built around: at zero the gym is
// actively turning customers away, below reorder level it merely might.
func (i StockItem) OutOfStock() bool { return i.StockQty <= 0 }

// StockQueue backs GET /api/v1/queues/stock.
type StockQueue struct {
	Groups []StockGroup `json:"groups"`

	// Gym-wide, so the reader has the denominator. "2 of 11" reads very
	// differently from "2".
	TotalProducts   int `json:"total_products"`
	TotalFlagged    int `json:"total_flagged"`
	TotalOutOfStock int `json:"total_out_of_stock"`
}

const (
	GroupOutOfStock = "out_of_stock"
	GroupLow        = "low"
)
