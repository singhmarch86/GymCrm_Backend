package pos

import (
	"context"
	"errors"
	"fmt"
	"math"
	"strings"
	"time"

	"gymcrm/internal/database"
	"gymcrm/internal/wallet"
)

var (
	ErrProductNotFound    = errors.New("product not found")
	ErrSaleNotFound       = errors.New("sale not found")
	ErrInsufficientStock  = errors.New("not enough stock")
	ErrNameRequired       = errors.New("product name is required")
	ErrPriceNegative      = errors.New("price cannot be negative")
	ErrNoItems            = errors.New("a sale needs at least one item")
	ErrQuantityZero       = errors.New("quantity cannot be zero")
	ErrRefundReason       = errors.New("a reason is required for a refund")
	ErrAlreadyRefunded    = errors.New("this sale has already been refunded")
	ErrCannotRefundRefund = errors.New("a refund cannot itself be refunded")
	// Paying from a wallet needs to know whose wallet.
	ErrWalletNeedsMember = errors.New("select the member to pay from their wallet")
)

// Service implements retail. See docs/FR-07-pos-inventory.md.
type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

func roundHalfUp(v float64) int64 { return int64(math.Round(v)) }

func paiseToRupees(p int64) float64 { return float64(p) / 100 }

// ─── Products ─────────────────────────────────────────────────────────────────

func (s *Service) CreateProduct(ctx context.Context, req CreateProductRequest) (*Product, error) {
	if strings.TrimSpace(req.Name) == "" {
		return nil, ErrNameRequired
	}
	if req.PriceInPaise < 0 || req.CostInPaise < 0 {
		return nil, ErrPriceNegative
	}
	tc := database.MustGetTenant(ctx)

	rate := 18.0
	if req.TaxRatePct != nil {
		rate = *req.TaxRatePct
	}
	p := &Product{
		GymID: tc.GymID(), SKU: optional(req.SKU), Name: strings.TrimSpace(req.Name),
		Category: optional(req.Category), Description: optional(req.Description),
		PriceInPaise: req.PriceInPaise, CostInPaise: req.CostInPaise,
		TaxRatePct: rate, ReorderLevel: req.ReorderLevel, IsActive: true,
	}
	if err := s.repo.CreateProduct(ctx, p); err != nil {
		return nil, fmt.Errorf("create product: %w", err)
	}

	// Opening stock is recorded as a purchase movement rather than written
	// straight onto the product, so even the initial level has a trail.
	if req.OpeningStock > 0 {
		updated, err := s.repo.AdjustStock(ctx, p.ID, req.OpeningStock, MovementPurchase, "Opening stock")
		if err != nil {
			return nil, fmt.Errorf("create product: opening stock: %w", err)
		}
		return updated, nil
	}
	return p, nil
}

func (s *Service) ListProducts(ctx context.Context, search string, activeOnly, lowStockOnly bool) ([]Product, error) {
	out, err := s.repo.ListProducts(ctx, search, activeOnly, lowStockOnly)
	if err != nil {
		return nil, fmt.Errorf("list products: %w", err)
	}
	return out, nil
}

func (s *Service) UpdateProduct(ctx context.Context, id int64, req UpdateProductRequest) (*Product, error) {
	existing, err := s.repo.FindProduct(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("update product: %w", err)
	}
	if existing == nil {
		return nil, ErrProductNotFound
	}

	fields := map[string]any{}
	if req.Name != nil {
		if strings.TrimSpace(*req.Name) == "" {
			return nil, ErrNameRequired
		}
		fields["name"] = strings.TrimSpace(*req.Name)
	}
	if req.SKU != nil {
		fields["sku"] = optional(*req.SKU)
	}
	if req.Category != nil {
		fields["category"] = optional(*req.Category)
	}
	if req.Description != nil {
		fields["description"] = optional(*req.Description)
	}
	if req.PriceInPaise != nil {
		if *req.PriceInPaise < 0 {
			return nil, ErrPriceNegative
		}
		fields["price_in_paise"] = *req.PriceInPaise
	}
	if req.CostInPaise != nil {
		if *req.CostInPaise < 0 {
			return nil, ErrPriceNegative
		}
		fields["cost_in_paise"] = *req.CostInPaise
	}
	if req.TaxRatePct != nil {
		if *req.TaxRatePct < 0 || *req.TaxRatePct > 100 {
			return nil, fmt.Errorf("tax rate must be between 0 and 100")
		}
		fields["tax_rate_pct"] = *req.TaxRatePct
	}
	if req.ReorderLevel != nil {
		fields["reorder_level"] = *req.ReorderLevel
	}
	if req.IsActive != nil {
		fields["is_active"] = *req.IsActive
	}

	if len(fields) > 0 {
		if err := s.repo.UpdateProduct(ctx, id, fields); err != nil {
			return nil, fmt.Errorf("update product: %w", err)
		}
	}
	return s.repo.FindProduct(ctx, id)
}

func (s *Service) DeleteProduct(ctx context.Context, id int64) error {
	existing, err := s.repo.FindProduct(ctx, id)
	if err != nil {
		return fmt.Errorf("delete product: %w", err)
	}
	if existing == nil {
		return ErrProductNotFound
	}
	// Soft delete: sale_items reference this product and history must survive.
	return s.repo.SoftDeleteProduct(ctx, id)
}

// AdjustStock records a manual stock change — a delivery, a count correction,
// breakage. Never silently: the movement carries the reason.
func (s *Service) AdjustStock(ctx context.Context, productID int64, req AdjustStockRequest) (*Product, error) {
	if req.Quantity == 0 {
		return nil, ErrQuantityZero
	}
	mt := req.MovementType
	switch mt {
	case MovementPurchase, MovementAdjustment, MovementReturn, MovementWastage:
	default:
		mt = MovementAdjustment
	}
	p, err := s.repo.AdjustStock(ctx, productID, req.Quantity, mt, req.Reason)
	if err != nil {
		if errors.Is(err, ErrProductNotFound) {
			return nil, err
		}
		return nil, fmt.Errorf("adjust stock: %w", err)
	}
	return p, nil
}

func (s *Service) StockHistory(ctx context.Context, productID int64) ([]StockMovement, error) {
	out, err := s.repo.ListMovements(ctx, productID, 100)
	if err != nil {
		return nil, fmt.Errorf("stock history: %w", err)
	}
	return out, nil
}

// ─── Sales ────────────────────────────────────────────────────────────────────

func (s *Service) RecordSale(ctx context.Context, req CreateSaleRequest) (*SaleResponse, error) {
	if len(req.Items) == 0 {
		return nil, ErrNoItems
	}
	lines := make([]lineInput, 0, len(req.Items))
	for _, it := range req.Items {
		if it.Quantity <= 0 {
			return nil, ErrQuantityZero
		}
		lines = append(lines, lineInput{ProductID: it.ProductID, Quantity: it.Quantity})
	}

	allowNegative, err := s.repo.allowNegativeStock(ctx)
	if err != nil {
		return nil, fmt.Errorf("record sale: settings: %w", err)
	}

	mode := req.PaymentMode
	if mode == "" {
		mode = "cash"
	}
	sale := &Sale{
		MemberID: req.MemberID, PaymentMode: mode,
		DiscountInPaise: req.DiscountInPaise, Notes: optional(req.Notes),
	}

	saved, items, err := s.repo.RecordSale(ctx, sale, lines, allowNegative)
	if err != nil {
		// Stock, wallet and member errors are the user's problem to fix, so
		// they pass through with their own message rather than becoming a 500.
		if errors.Is(err, ErrInsufficientStock) || errors.Is(err, ErrProductNotFound) ||
			errors.Is(err, ErrWalletNeedsMember) || errors.Is(err, wallet.ErrInsufficientFunds) ||
			errors.Is(err, wallet.ErrMemberNotFound) {
			return nil, err
		}
		return nil, fmt.Errorf("record sale: %w", err)
	}
	return toSaleResponse(*saved, items, nil), nil
}

// Refund reverses a sale by recording a NEW sale with negative quantities. The
// original is never edited or deleted — a till that can be rewritten after the
// fact is a till nobody can reconcile (FR-07 §2.1).
func (s *Service) Refund(ctx context.Context, saleID int64, req RefundRequest) (*SaleResponse, error) {
	if strings.TrimSpace(req.Reason) == "" {
		return nil, ErrRefundReason
	}
	original, err := s.repo.FindSale(ctx, saleID)
	if err != nil {
		return nil, fmt.Errorf("refund: %w", err)
	}
	if original == nil {
		return nil, ErrSaleNotFound
	}
	if original.IsRefund {
		return nil, ErrCannotRefundRefund
	}

	items, err := s.repo.ListSaleItems(ctx, saleID)
	if err != nil {
		return nil, fmt.Errorf("refund: items: %w", err)
	}

	lines := make([]lineInput, 0, len(items))
	for _, it := range items {
		lines = append(lines, lineInput{ProductID: it.ProductID, Quantity: -it.Quantity})
	}

	reason := strings.TrimSpace(req.Reason)
	refund := &Sale{
		MemberID: original.MemberID, PaymentMode: original.PaymentMode,
		IsRefund: true, RefundOfSaleID: &saleID, Reason: &reason,
	}
	// Negative quantities put stock back, so overselling checks don't apply.
	saved, refundItems, err := s.repo.RecordSale(ctx, refund, lines, true)
	if err != nil {
		return nil, fmt.Errorf("refund: %w", err)
	}
	return toSaleResponse(*saved, refundItems, nil), nil
}

func (s *Service) GetSale(ctx context.Context, id int64) (*SaleResponse, error) {
	sale, err := s.repo.FindSale(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("get sale: %w", err)
	}
	if sale == nil {
		return nil, ErrSaleNotFound
	}
	items, err := s.repo.ListSaleItems(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("get sale: items: %w", err)
	}
	return toSaleResponse(*sale, items, nil), nil
}

func (s *Service) ListSales(ctx context.Context, from, to time.Time, memberID *int64) ([]SaleResponse, error) {
	rows, err := s.repo.ListSales(ctx, from, to, memberID)
	if err != nil {
		return nil, fmt.Errorf("list sales: %w", err)
	}
	out := make([]SaleResponse, 0, len(rows))
	for _, r := range rows {
		out = append(out, *toSaleResponse(r.Sale, nil, r.MemberName))
	}
	return out, nil
}

func (s *Service) Summary(ctx context.Context, from, to time.Time) (*SummaryResponse, error) {
	sum, err := s.repo.Summary(ctx, from, to)
	if err != nil {
		return nil, fmt.Errorf("summary: %w", err)
	}
	return &SummaryResponse{
		SaleCount: sum.SaleCount, UnitsSold: sum.UnitsSold,
		RevenueInPaise: sum.RevenueInPaise, RevenueInRupees: paiseToRupees(sum.RevenueInPaise),
		CostInPaise: sum.CostInPaise,
		// Margin is why cost is captured at all — revenue alone can't tell a gym
		// whether the retail shelf is worth the space.
		MarginInPaise:     sum.RevenueInPaise - sum.CostInPaise,
		StockValueInPaise: sum.StockValueInPaise,
		LowStockCount:     sum.LowStockCount,
	}, nil
}

func toSaleResponse(s Sale, items []SaleItem, memberName *string) *SaleResponse {
	lines := make([]SaleItemResponse, 0, len(items))
	for _, it := range items {
		lines = append(lines, SaleItemResponse{
			ProductID: it.ProductID, ProductName: it.ProductName,
			Quantity: it.Quantity, UnitPriceInPaise: it.UnitPriceInPaise,
			LineTotalInPaise: it.LineTotalInPaise,
		})
	}
	return &SaleResponse{
		ID: s.ID, MemberID: s.MemberID, MemberName: memberName,
		SubtotalInPaise: s.SubtotalInPaise, TaxInPaise: s.TaxInPaise,
		DiscountInPaise: s.DiscountInPaise, TotalInPaise: s.TotalInPaise,
		TotalInRupees: paiseToRupees(s.TotalInPaise),
		PaymentMode:   s.PaymentMode, IsRefund: s.IsRefund,
		RefundOfSaleID: s.RefundOfSaleID, Reason: s.Reason,
		CreatedAt: s.CreatedAt, Items: lines,
	}
}
