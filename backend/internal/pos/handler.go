package pos

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"gymcrm/internal/shared/response"
	"gymcrm/internal/wallet"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/products", h.CreateProduct)
	mux.HandleFunc("GET /api/v1/products", h.ListProducts)
	mux.HandleFunc("PUT /api/v1/products/{id}", h.UpdateProduct)
	mux.HandleFunc("DELETE /api/v1/products/{id}", h.DeleteProduct)
	mux.HandleFunc("POST /api/v1/products/{id}/stock", h.AdjustStock)
	mux.HandleFunc("GET /api/v1/products/{id}/stock-history", h.StockHistory)

	mux.HandleFunc("POST /api/v1/sales", h.RecordSale)
	mux.HandleFunc("GET /api/v1/sales", h.ListSales)
	mux.HandleFunc("GET /api/v1/sales/{id}", h.GetSale)
	mux.HandleFunc("POST /api/v1/sales/{id}/refund", h.Refund)
	mux.HandleFunc("GET /api/v1/retail/summary", h.Summary)
}

// CreateProduct godoc
// @Summary      Add a product
// @Tags         retail
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      CreateProductRequest  true  "Product"
// @Success      201   {object}  Product
// @Router       /api/v1/products [post]
func (h *Handler) CreateProduct(w http.ResponseWriter, r *http.Request) {
	var req CreateProductRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.CreateProduct(r.Context(), req)
	if err != nil {
		writeErr(w, err, "create product")
		return
	}
	response.Created(w, res)
}

// ListProducts godoc
// @Summary      List products
// @Tags         retail
// @Produce      json
// @Security     BearerAuth
// @Param        search     query     string  false  "Name, SKU or category"
// @Param        low_stock  query     bool    false  "Only products at or below reorder level"
// @Success      200        {array}   Product
// @Router       /api/v1/products [get]
func (h *Handler) ListProducts(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	res, err := h.svc.ListProducts(
		r.Context(),
		q.Get("search"),
		q.Get("active_only") == "true",
		q.Get("low_stock") == "true",
	)
	if err != nil {
		writeErr(w, err, "list products")
		return
	}
	response.OK(w, res)
}

// UpdateProduct godoc
// @Summary      Edit a product
// @Description  Stock is not editable here — use the stock adjustment endpoint.
// @Tags         retail
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                   true  "Product ID"
// @Param        body  body      UpdateProductRequest  true  "Changes"
// @Success      200   {object}  Product
// @Router       /api/v1/products/{id} [put]
func (h *Handler) UpdateProduct(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	var req UpdateProductRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.UpdateProduct(r.Context(), id, req)
	if err != nil {
		writeErr(w, err, "update product")
		return
	}
	response.OK(w, res)
}

// DeleteProduct godoc
// @Summary      Retire a product
// @Description  Soft delete — past sales referencing it must survive.
// @Tags         retail
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Product ID"
// @Success      200  {object}  response.Envelope
// @Router       /api/v1/products/{id} [delete]
func (h *Handler) DeleteProduct(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	if err := h.svc.DeleteProduct(r.Context(), id); err != nil {
		writeErr(w, err, "delete product")
		return
	}
	response.OK(w, map[string]string{"status": "deleted"})
}

// AdjustStock godoc
// @Summary      Adjust stock
// @Description  Positive adds, negative removes. Always recorded with a reason.
// @Tags         retail
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                 true  "Product ID"
// @Param        body  body      AdjustStockRequest  true  "Adjustment"
// @Success      200   {object}  Product
// @Router       /api/v1/products/{id}/stock [post]
func (h *Handler) AdjustStock(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	var req AdjustStockRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.AdjustStock(r.Context(), id, req)
	if err != nil {
		writeErr(w, err, "adjust stock")
		return
	}
	response.OK(w, res)
}

// StockHistory godoc
// @Summary      Why this product's stock is what it is
// @Tags         retail
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Product ID"
// @Success      200  {array}   StockMovement
// @Router       /api/v1/products/{id}/stock-history [get]
func (h *Handler) StockHistory(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	res, err := h.svc.StockHistory(r.Context(), id)
	if err != nil {
		writeErr(w, err, "stock history")
		return
	}
	response.OK(w, res)
}

// RecordSale godoc
// @Summary      Record a counter sale
// @Description  Decrements stock atomically. Blocked if stock is short, unless the gym allows negative stock.
// @Tags         retail
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      CreateSaleRequest  true  "Sale"
// @Success      201   {object}  SaleResponse
// @Failure      409   {object}  response.Envelope  "Not enough stock"
// @Router       /api/v1/sales [post]
func (h *Handler) RecordSale(w http.ResponseWriter, r *http.Request) {
	var req CreateSaleRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.RecordSale(r.Context(), req)
	if err != nil {
		writeErr(w, err, "record sale")
		return
	}
	response.Created(w, res)
}

// ListSales godoc
// @Summary      Sales in a date range
// @Tags         retail
// @Produce      json
// @Security     BearerAuth
// @Param        from  query     string  false  "YYYY-MM-DD, defaults to 30 days ago"
// @Param        to    query     string  false  "YYYY-MM-DD, defaults to today"
// @Success      200   {array}   SaleResponse
// @Router       /api/v1/sales [get]
func (h *Handler) ListSales(w http.ResponseWriter, r *http.Request) {
	from, to, err := dateRange(r)
	if err != nil {
		response.BadRequest(w, err.Error())
		return
	}
	var memberID *int64
	if raw := r.URL.Query().Get("member_id"); raw != "" {
		id, err := strconv.ParseInt(raw, 10, 64)
		if err != nil {
			response.BadRequest(w, "invalid member_id")
			return
		}
		memberID = &id
	}
	res, err := h.svc.ListSales(r.Context(), from, to, memberID)
	if err != nil {
		writeErr(w, err, "list sales")
		return
	}
	response.OK(w, res)
}

// GetSale godoc
// @Summary      One sale with its lines
// @Tags         retail
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Sale ID"
// @Success      200  {object}  SaleResponse
// @Router       /api/v1/sales/{id} [get]
func (h *Handler) GetSale(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	res, err := h.svc.GetSale(r.Context(), id)
	if err != nil {
		writeErr(w, err, "get sale")
		return
	}
	response.OK(w, res)
}

// Refund godoc
// @Summary      Refund a sale
// @Description  Creates a reversing sale and returns the stock. The original is never edited.
// @Tags         retail
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int            true  "Sale ID"
// @Param        body  body      RefundRequest  true  "Reason"
// @Success      201   {object}  SaleResponse
// @Failure      422   {object}  response.Envelope  "Reason missing"
// @Router       /api/v1/sales/{id}/refund [post]
func (h *Handler) Refund(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	var req RefundRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.Refund(r.Context(), id, req)
	if err != nil {
		writeErr(w, err, "refund")
		return
	}
	response.Created(w, res)
}

// Summary godoc
// @Summary      Retail summary
// @Tags         retail
// @Produce      json
// @Security     BearerAuth
// @Param        from  query     string  false  "YYYY-MM-DD"
// @Param        to    query     string  false  "YYYY-MM-DD"
// @Success      200   {object}  SummaryResponse
// @Router       /api/v1/retail/summary [get]
func (h *Handler) Summary(w http.ResponseWriter, r *http.Request) {
	from, to, err := dateRange(r)
	if err != nil {
		response.BadRequest(w, err.Error())
		return
	}
	res, err := h.svc.Summary(r.Context(), from, to)
	if err != nil {
		writeErr(w, err, "summary")
		return
	}
	response.OK(w, res)
}

// ─── helpers ──────────────────────────────────────────────────────────────────

func dateRange(r *http.Request) (time.Time, time.Time, error) {
	now := time.Now()
	from := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC).AddDate(0, 0, -30)
	to := time.Date(now.Year(), now.Month(), now.Day(), 23, 59, 59, 0, time.UTC)

	if raw := strings.TrimSpace(r.URL.Query().Get("from")); raw != "" {
		t, err := time.Parse("2006-01-02", raw)
		if err != nil {
			return from, to, errBadDate
		}
		from = t
	}
	if raw := strings.TrimSpace(r.URL.Query().Get("to")); raw != "" {
		t, err := time.Parse("2006-01-02", raw)
		if err != nil {
			return from, to, errBadDate
		}
		to = time.Date(t.Year(), t.Month(), t.Day(), 23, 59, 59, 0, time.UTC)
	}
	return from, to, nil
}

var errBadDate = errors.New("dates must be YYYY-MM-DD")

func pathID(w http.ResponseWriter, r *http.Request, param string) (int64, bool) {
	id, err := strconv.ParseInt(r.PathValue(param), 10, 64)
	if err != nil || id <= 0 {
		response.BadRequest(w, "invalid "+param)
		return 0, false
	}
	return id, true
}

func decode(w http.ResponseWriter, r *http.Request, dst any) bool {
	if r.Body == nil || r.ContentLength == 0 {
		return true
	}
	if err := json.NewDecoder(r.Body).Decode(dst); err != nil {
		response.BadRequest(w, "invalid request body")
		return false
	}
	return true
}

func writeErr(w http.ResponseWriter, err error, op string) {
	switch {
	case errors.Is(err, ErrProductNotFound), errors.Is(err, ErrSaleNotFound):
		response.NotFound(w, err.Error())

	case errors.Is(err, ErrInsufficientStock),
		errors.Is(err, wallet.ErrInsufficientFunds),
		errors.Is(err, ErrAlreadyRefunded),
		errors.Is(err, ErrCannotRefundRefund):
		response.Conflict(w, err.Error())

	case errors.Is(err, ErrWalletNeedsMember),
		errors.Is(err, ErrNameRequired),
		errors.Is(err, ErrPriceNegative),
		errors.Is(err, ErrNoItems),
		errors.Is(err, ErrQuantityZero),
		errors.Is(err, ErrRefundReason),
		errors.Is(err, errBadDate):
		response.UnprocessableEntity(w, err.Error())

	default:
		if strings.Contains(err.Error(), "must be between") {
			response.UnprocessableEntity(w, err.Error())
			return
		}
		log.Printf("pos %s: %v", op, err)
		response.InternalServerError(w)
	}
}
