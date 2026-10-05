package stocktransfer

import (
	"context"
	"fmt"
	"strings"

	"gorm.io/gorm"

	"gymcrm/internal/database"
)

// SalesWindowDays is the trailing period the surplus test reads. Long enough
// that one quiet fortnight does not condemn a product, short enough that last
// winter's protein sales do not justify this summer's shelf.
const SalesWindowDays = 60

type Service struct {
	repo *Repository
	db   *gorm.DB
}

func NewService(repo *Repository, db *gorm.DB) *Service {
	return &Service{repo: repo, db: db}
}

// Chain answers "where in the chain is this item", for every item.
func (s *Service) Chain(ctx context.Context) (*ChainStock, error) {
	tc := database.MustGetTenant(ctx)

	branches, err := s.repo.VisibleBranches(ctx, tc.UserID())
	if err != nil {
		return nil, fmt.Errorf("chain stock: branches: %w", err)
	}

	// A single-branch gym is the common case and must not look broken. It gets
	// its own branch back with its own stock — one column, no comparisons, and
	// nothing movable, which is the honest answer rather than an empty screen.
	if len(branches) == 0 {
		name, err := s.repo.BranchLabel(ctx, tc.GymID())
		if err != nil {
			return nil, fmt.Errorf("chain stock: branch label: %w", err)
		}
		branches = []BranchRef{{GymID: tc.GymID(), Name: name}}
	}

	ids := make([]int64, 0, len(branches))
	for _, b := range branches {
		ids = append(ids, b.GymID)
	}

	rows, err := s.repo.StockAcross(ctx, ids, SalesWindowDays)
	if err != nil {
		return nil, fmt.Errorf("chain stock: %w", err)
	}

	out := &ChainStock{Branches: branches, Items: []ChainItem{}, ShortEverywhere: []string{}}

	// Grouped in encounter order, which the query already made alphabetical by
	// product name. Deliberately not a map iteration: Go randomises those, and
	// a list that reorders itself between two refreshes of the same unchanged
	// data reads as data changing.
	index := map[string]int{}
	for _, row := range rows {
		key, matchedBy := matchKey(row.SKU, row.Name)

		i, seen := index[key]
		if !seen {
			i = len(out.Items)
			index[key] = i
			out.Items = append(out.Items, ChainItem{
				Key: key, MatchedBy: matchedBy, Name: row.Name,
				SKU: row.SKU, Category: row.Category,
				Branches: []BranchStock{},
			})
		}

		short := row.StockQty <= row.ReorderLevel
		long := isSurplus(row.StockQty, row.ReorderLevel, row.SoldRecently)

		item := &out.Items[i]
		item.Branches = append(item.Branches, BranchStock{
			GymID:        row.GymID,
			Branch:       label(row.Branch, row.BranchName),
			ProductID:    row.ProductID,
			StockQty:     row.StockQty,
			ReorderLevel: row.ReorderLevel,
			CostInPaise:  row.CostInPaise,
			PriceInPaise: row.PriceInPaise,
			IsShort:      short,
			IsLong:       long,
		})
		item.TotalQty += row.StockQty
		if short {
			item.ShortBranches++
		}
		if long {
			item.LongBranches++
		}
	}

	for i := range out.Items {
		it := &out.Items[i]
		it.Movable = it.ShortBranches > 0 && it.LongBranches > 0
		if it.Movable {
			out.MovableCount++
		}
		// Short at every branch that carries it, with no surplus anywhere.
		// No transfer helps; this is a purchase order.
		if it.ShortBranches == len(it.Branches) && it.LongBranches == 0 {
			out.ShortEverywhere = append(out.ShortEverywhere, it.Name)
		}
	}

	return out, nil
}

// isSurplus is the same test the single-branch stock report uses, so the two
// screens never disagree about what "too much" means.
//
// Zero recent sales counts as surplus only when there is more on the shelf
// than the reorder level. A product sitting at or below reorder has a supply
// problem, not a surplus, whatever its sales look like.
func isSurplus(stockQty, reorderLevel, soldRecently int) bool {
	if stockQty <= reorderLevel || stockQty == 0 {
		return false
	}
	if soldRecently == 0 {
		return true
	}
	daysOfCover := float64(stockQty) * float64(SalesWindowDays) / float64(soldRecently)
	return daysOfCover > OverstockedDays
}

// matchKey decides what counts as the same item at two branches.
//
// SKU when there is one, because that is what a SKU is for. Name otherwise,
// which is a guess — two branches can label the same tub differently and will
// then show as two items. Reported via MatchedBy rather than hidden, so a
// reader who sees an item split in two knows to set a SKU.
func matchKey(sku *string, name string) (string, string) {
	if sku != nil && strings.TrimSpace(*sku) != "" {
		return "sku:" + strings.ToLower(strings.TrimSpace(*sku)), "sku"
	}
	return "name:" + strings.ToLower(strings.TrimSpace(name)), "name"
}

// ─── Transfers ────────────────────────────────────────────────────────────────

// Send moves stock from the caller's branch to another they hold.
//
// Not owner-only, unlike staff and trainer transfers. Moving a box of protein
// is a front-desk act — the person who notices the shelf is empty is the
// person standing at it, and requiring an owner would mean it does not happen.
// The ledger records who did it, which is the control that suits the size of
// the decision.
func (s *Service) Send(ctx context.Context, productID, toGymID int64, qty int, reason string) (*Transfer, error) {
	tc := database.MustGetTenant(ctx)

	if qty < 1 || qty > MaxTransferQty {
		return nil, ErrBadQuantity
	}
	if toGymID == tc.GymID() {
		return nil, ErrSameBranch
	}
	if err := s.checkTarget(ctx, toGymID); err != nil {
		return nil, err
	}

	t, err := s.repo.Move(ctx, productID, toGymID, qty, reason)
	if err != nil {
		switch {
		case err == ErrProductNotFound, err == ErrNotEnoughStock:
			return nil, err
		default:
			return nil, fmt.Errorf("transfer stock: %w", err)
		}
	}
	return t, nil
}

// checkTarget mirrors the guard the member and staff transfers use: the
// destination must be a branch the caller holds, inside their own
// organization.
func (s *Service) checkTarget(ctx context.Context, toGymID int64) error {
	tc := database.MustGetTenant(ctx)

	var role string
	if err := s.db.WithContext(ctx).Table("user_gym_access").
		Select("role").Where("user_id = ? AND gym_id = ?", tc.UserID(), toGymID).
		Limit(1).Scan(&role).Error; err != nil {
		return fmt.Errorf("transfer stock: access check: %w", err)
	}
	if role == "" {
		return ErrNoAccess
	}

	var orgID *int64
	if err := s.db.WithContext(ctx).Table("gyms").
		Select("organization_id").Where("id = ?", tc.GymID()).
		Limit(1).Scan(&orgID).Error; err != nil {
		return fmt.Errorf("transfer stock: %w", err)
	}
	if orgID == nil {
		return ErrDifferentOrg
	}

	var n int64
	if err := s.db.WithContext(ctx).Table("gyms").
		Where("id = ? AND organization_id = ?", toGymID, *orgID).
		Count(&n).Error; err != nil {
		return fmt.Errorf("transfer stock: %w", err)
	}
	if n == 0 {
		return ErrDifferentOrg
	}
	return nil
}

// History is the transfer ledger for the caller's branch.
func (s *Service) History(ctx context.Context, limit int) ([]TransferRow, error) {
	tc := database.MustGetTenant(ctx)
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	return s.repo.History(ctx, tc.GymID(), limit)
}
