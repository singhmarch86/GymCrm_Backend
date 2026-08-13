package stockreport

// Stock analytics (FR-23).
//
// The low-stock queue answers "what is nearly gone" by comparing stock against
// a reorder level somebody typed in once. This answers the question that
// actually decides money: how long will it last, and is it worth restocking at
// all.
//
// On the gym's own data those two answers disagree, which is the reason this
// exists. Pre-workout is flagged low at 3 units and has twenty-five days of
// cover; mineral water is not flagged at 57 units and has twenty-four. The
// reorder levels were set without reference to how fast anything sells, and
// no amount of staring at the queue reveals that.
//
// Everything here is descriptive. Nothing reorders anything, and no number is
// presented as a forecast — the rate is what sold in the window the reader
// chose, and if that window contained a festival or a closure the rate says so
// and the reader knows why.

// DefaultLeadDays is how long a restock is assumed to take.
//
// The gym has not been asked yet, so it is stated as an assumption the caller
// can override rather than buried in a comparison. Every "reorder now" verdict
// below is really "will run out before a delivery could arrive", and that
// sentence is meaningless without this number.
const DefaultLeadDays = 7

// OverstockedDays is when stock stops being cover and starts being money
// asleep on a shelf. Three months of a slow mover is capital that could have
// bought something that sells.
const OverstockedDays = 90

// Verdicts. Ordered by how much they should worry somebody.
const (
	VerdictOutOfStock  = "out_of_stock"
	VerdictReorderNow  = "reorder_now"
	VerdictDead        = "dead"
	VerdictOverstocked = "overstocked"
	VerdictHealthy     = "healthy"
)

// ProductStock is one product's position: what it sold, what it earned, and
// how long what is left will last.
type ProductStock struct {
	ProductID int64  `json:"product_id"`
	Name      string `json:"name"`
	SKU       string `json:"sku,omitempty"`
	Category  string `json:"category,omitempty"`

	StockQty     int `json:"stock_qty"`
	ReorderLevel int `json:"reorder_level"`

	// Over the chosen window.
	UnitsSold      int   `json:"units_sold"`
	RevenueInPaise int64 `json:"revenue_in_paise"`

	// Revenue minus what those units cost, using the cost snapshotted on each
	// sale line rather than today's cost. A supplier price rise must not
	// rewrite last month's profit.
	ProfitInPaise int64 `json:"profit_in_paise"`
	MarginPct     int   `json:"margin_pct"`

	// Units per day across the window. The window's own rate, not a forecast.
	PerDay float64 `json:"per_day"`

	// How many days the shelf lasts at that rate. Null when nothing sold —
	// dividing by zero would report "infinite cover", which reads as healthy
	// when it means the opposite.
	DaysCover *int `json:"days_cover,omitempty"`

	// What the reorder level would be if it were set from the sale rate and
	// the lead time. Advisory: shown next to the current one so a mismatch is
	// visible, never written back.
	SuggestedReorder int `json:"suggested_reorder"`

	// Capital sitting in this product, at cost.
	StockValueInPaise int64 `json:"stock_value_in_paise"`

	Verdict string `json:"verdict"`

	// Why the verdict says what it says, in the reader's words.
	Note string `json:"note"`
}

// CategoryTotal groups the shelf by category.
type CategoryTotal struct {
	Category       string `json:"category"`
	UnitsSold      int    `json:"units_sold"`
	RevenueInPaise int64  `json:"revenue_in_paise"`
	ProfitInPaise  int64  `json:"profit_in_paise"`
	SharePct       int    `json:"share_pct"`
}

// StockReport backs GET /api/v1/stock/analytics.
type StockReport struct {
	From     string `json:"from"`
	To       string `json:"to"`
	Days     int    `json:"days"`
	LeadDays int    `json:"lead_days"`

	UnitsSold      int   `json:"units_sold"`
	RevenueInPaise int64 `json:"revenue_in_paise"`
	ProfitInPaise  int64 `json:"profit_in_paise"`

	// Everything on the shelf right now, at cost. What the gym has spent and
	// not yet recovered.
	StockValueInPaise int64 `json:"stock_value_in_paise"`

	// The part of that which has not moved at all in the window. The single
	// most useful number here: money the gym has already spent that is doing
	// nothing.
	DeadValueInPaise int64 `json:"dead_value_in_paise"`
	DeadCount        int   `json:"dead_count"`

	// Products whose reorder level disagrees with how fast they sell. The
	// reason to look at this screen rather than the low-stock queue.
	MismatchCount int `json:"mismatch_count"`

	Products   []ProductStock  `json:"products"`
	Categories []CategoryTotal `json:"categories"`
}
