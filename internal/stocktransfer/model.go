package stocktransfer

import "time"

// Inventory across branches (FR-22).
//
// Two questions, one module. "Where in the chain is this item" — answered by
// the chain view, which is read-only and covers every branch the caller holds.
// "Move some of it there" — answered by a transfer, which is a pair of stock
// movements and a header.
//
// Deliberately not a stock *pool*. Each branch keeps its own product rows and
// its own levels; nothing here lets one branch sell another's stock. A shared
// pool would let the front desk at one location promise an item sitting in a
// cupboard twenty minutes away, and the member would be the one who finds out.

// Movement types written by a transfer. Both sides are recorded so a product's
// history at either branch explains itself without consulting the other.
const (
	MovementTransferOut = "transfer_out"
	MovementTransferIn  = "transfer_in"
)

// Transfer is the header tying the two movements together.
type Transfer struct {
	ID int64 `gorm:"primaryKey;autoIncrement" json:"id"`

	FromGymID int64 `gorm:"not null" json:"from_gym_id"`
	ToGymID   int64 `gorm:"not null" json:"to_gym_id"`

	FromProductID int64 `gorm:"not null" json:"from_product_id"`
	ToProductID   int64 `gorm:"not null" json:"to_product_id"`

	Quantity int `gorm:"not null" json:"quantity"`

	UnitCostInPaise int64 `gorm:"not null;default:0" json:"unit_cost_in_paise"`
	ValueInPaise    int64 `gorm:"not null;default:0" json:"value_in_paise"`

	Reason          *string   `gorm:"type:text" json:"reason,omitempty"`
	CreatedByUserID int64     `gorm:"not null" json:"created_by_user_id"`
	CreatedAt       time.Time `gorm:"autoCreateTime" json:"created_at"`
}

func (Transfer) TableName() string { return "stock_transfers" }

// TransferRow is a transfer as the ledger shows it: names rather than ids,
// and a direction relative to the branch the reader is standing in.
type TransferRow struct {
	ID        int64     `json:"id"`
	Product   string    `json:"product"`
	Quantity  int       `json:"quantity"`
	FromGymID int64     `json:"from_gym_id"`
	ToGymID   int64     `json:"to_gym_id"`
	FromName  string    `json:"from_branch"`
	ToName    string    `json:"to_branch"`
	Direction string    `json:"direction"` // "out" | "in", from the caller's branch
	Value     int64     `json:"value_in_paise"`
	Reason    *string   `json:"reason,omitempty"`
	By        string    `json:"by"`
	At        time.Time `json:"at"`
}

// ─── The chain view ───────────────────────────────────────────────────────────

// ChainItem is one product across every branch the caller can see.
//
// Products are per-gym rows, so the "same" item is several rows that have to
// be matched. Key explains how, because the match is a guess and the reader
// deserves to know which kind: an item matched by SKU is the same item, one
// matched by name probably is.
type ChainItem struct {
	Key       string  `json:"key"`
	MatchedBy string  `json:"matched_by"` // "sku" | "name"
	Name      string  `json:"name"`
	SKU       *string `json:"sku,omitempty"`
	Category  *string `json:"category,omitempty"`

	Branches []BranchStock `json:"branches"`

	TotalQty int `json:"total_qty"`

	// Branches carrying the item that are at or below their own reorder level,
	// alongside those holding more than they are likely to sell. Both counts,
	// not a verdict: the module reports the imbalance and stops. Which way the
	// van should drive is the owner's call, and a system that recommends it
	// would be guessing at delivery cost, footfall and who has a car.
	ShortBranches int `json:"short_branches"`
	LongBranches  int `json:"long_branches"`

	// True when at least one branch is short while another holds a surplus —
	// the only case where a transfer is even worth considering.
	Movable bool `json:"movable"`
}

// BranchStock is one branch's holding of one item.
type BranchStock struct {
	GymID        int64  `json:"gym_id"`
	Branch       string `json:"branch"`
	ProductID    int64  `json:"product_id"`
	StockQty     int    `json:"stock_qty"`
	ReorderLevel int    `json:"reorder_level"`
	CostInPaise  int64  `json:"cost_in_paise"`
	PriceInPaise int64  `json:"price_in_paise"`
	IsShort      bool   `json:"is_short"`
	IsLong       bool   `json:"is_long"`
}

// ChainStock is the whole answer: every branch, every matched item.
type ChainStock struct {
	Branches []BranchRef `json:"branches"`
	Items    []ChainItem `json:"items"`

	// How many items could be rebalanced without buying anything. The headline
	// figure, and the reason the screen exists.
	MovableCount int `json:"movable_count"`

	// Items short at every branch that carries them. Called out separately
	// because no transfer fixes these — they need a purchase order, and
	// leaving them in the same list as the movable ones would send somebody
	// looking for stock that the chain does not have.
	ShortEverywhere []string `json:"short_everywhere"`
}

// BranchRef is enough to label a column.
type BranchRef struct {
	GymID int64  `json:"gym_id"`
	Name  string `json:"name"`
}

// OverstockedDays mirrors the single-branch stock report: stock that would
// take longer than this to sell at the recent rate is surplus, and surplus is
// what a transfer can draw on.
const OverstockedDays = 90

// MaxTransferQty is a sanity bound, not a business rule. A four-digit quantity
// in a gym shop is a typo far more often than it is a pallet.
const MaxTransferQty = 9999
