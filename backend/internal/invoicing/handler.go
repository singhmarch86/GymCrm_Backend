package invoicing

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"

	"gymcrm/internal/shared/response"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/invoices", h.Create)
	mux.HandleFunc("GET /api/v1/invoices", h.List)
	mux.HandleFunc("GET /api/v1/invoices/{id}", h.Get)
	mux.HandleFunc("DELETE /api/v1/invoices/{id}", h.DeleteDraft)
	mux.HandleFunc("POST /api/v1/invoices/{id}/items", h.AddItem)
	mux.HandleFunc("POST /api/v1/invoices/{id}/plan-items", h.AddPlanItem)
	mux.HandleFunc("DELETE /api/v1/invoices/{id}/items/{item_id}", h.RemoveItem)
	mux.HandleFunc("POST /api/v1/invoices/{id}/discount", h.ApplyDiscount)
	mux.HandleFunc("POST /api/v1/invoices/{id}/issue", h.Issue)
	mux.HandleFunc("POST /api/v1/invoices/{id}/cancel", h.Cancel)
	mux.HandleFunc("GET /api/v1/members/{member_id}/invoices", h.MemberInvoices)

	mux.HandleFunc("POST /api/v1/discounts", h.CreateDiscount)
	mux.HandleFunc("GET /api/v1/discounts", h.ListDiscounts)
	mux.HandleFunc("PUT /api/v1/discounts/{id}", h.UpdateDiscount)

	mux.HandleFunc("GET /api/v1/billing-settings", h.GetSettings)
	mux.HandleFunc("PUT /api/v1/billing-settings", h.UpdateSettings)
}

// Create godoc
// @Summary      Create a draft invoice
// @Tags         invoicing
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      CreateInvoiceRequest  true  "Invoice"
// @Success      201   {object}  InvoiceResponse
// @Router       /api/v1/invoices [post]
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	var req CreateInvoiceRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.CreateInvoice(r.Context(), req)
	if err != nil {
		writeErr(w, err, "create invoice")
		return
	}
	response.Created(w, res)
}

// List godoc
// @Summary      List invoices
// @Tags         invoicing
// @Produce      json
// @Security     BearerAuth
// @Param        status  query     string  false  "draft | issued | cancelled"
// @Success      200     {array}   InvoiceSummaryResponse
// @Router       /api/v1/invoices [get]
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	status := strings.TrimSpace(r.URL.Query().Get("status"))
	res, err := h.svc.ListInvoices(r.Context(), nil, status)
	if err != nil {
		writeErr(w, err, "list invoices")
		return
	}
	response.OK(w, res)
}

// MemberInvoices godoc
// @Summary      A member's invoices
// @Tags         invoicing
// @Produce      json
// @Security     BearerAuth
// @Param        member_id  path      int  true  "Member ID"
// @Success      200        {array}   InvoiceSummaryResponse
// @Router       /api/v1/members/{member_id}/invoices [get]
func (h *Handler) MemberInvoices(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "member_id")
	if !ok {
		return
	}
	res, err := h.svc.ListInvoices(r.Context(), &id, "")
	if err != nil {
		writeErr(w, err, "list member invoices")
		return
	}
	response.OK(w, res)
}

// Get godoc
// @Summary      Get one invoice with its line items
// @Tags         invoicing
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Invoice ID"
// @Success      200  {object}  InvoiceResponse
// @Failure      404  {object}  response.Envelope
// @Router       /api/v1/invoices/{id} [get]
func (h *Handler) Get(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	res, err := h.svc.GetInvoice(r.Context(), id)
	if err != nil {
		writeErr(w, err, "get invoice")
		return
	}
	response.OK(w, res)
}

// DeleteDraft godoc
// @Summary      Delete a draft invoice
// @Description  Drafts only — an issued invoice can be cancelled, never deleted.
// @Tags         invoicing
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Invoice ID"
// @Success      200  {object}  response.Envelope
// @Failure      409  {object}  response.Envelope
// @Router       /api/v1/invoices/{id} [delete]
func (h *Handler) DeleteDraft(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	if err := h.svc.DeleteDraft(r.Context(), id); err != nil {
		writeErr(w, err, "delete draft")
		return
	}
	response.OK(w, map[string]string{"status": "deleted"})
}

// AddItem godoc
// @Summary      Add a line item to a draft
// @Tags         invoicing
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int             true  "Invoice ID"
// @Param        body  body      AddItemRequest  true  "Line item"
// @Success      200   {object}  InvoiceResponse
// @Failure      409   {object}  response.Envelope  "Invoice is not a draft"
// @Router       /api/v1/invoices/{id}/items [post]
func (h *Handler) AddItem(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	var req AddItemRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.AddItem(r.Context(), id, req)
	if err != nil {
		writeErr(w, err, "add item")
		return
	}
	response.OK(w, res)
}

// AddPlanItem godoc
// @Summary      Add a line from the plan catalogue
// @Description  Price and name are snapshotted from the plan, not supplied by the client.
// @Tags         invoicing
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                 true  "Invoice ID"
// @Param        body  body      AddPlanItemRequest  true  "Plan"
// @Success      200   {object}  InvoiceResponse
// @Router       /api/v1/invoices/{id}/plan-items [post]
func (h *Handler) AddPlanItem(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	var req AddPlanItemRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.AddPlanItem(r.Context(), id, req)
	if err != nil {
		writeErr(w, err, "add plan item")
		return
	}
	response.OK(w, res)
}

// RemoveItem godoc
// @Summary      Remove a line item from a draft
// @Tags         invoicing
// @Produce      json
// @Security     BearerAuth
// @Param        id       path      int  true  "Invoice ID"
// @Param        item_id  path      int  true  "Item ID"
// @Success      200      {object}  InvoiceResponse
// @Router       /api/v1/invoices/{id}/items/{item_id} [delete]
func (h *Handler) RemoveItem(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	itemID, ok := pathID(w, r, "item_id")
	if !ok {
		return
	}
	res, err := h.svc.RemoveItem(r.Context(), id, itemID)
	if err != nil {
		writeErr(w, err, "remove item")
		return
	}
	response.OK(w, res)
}

// ApplyDiscount godoc
// @Summary      Apply (or clear) a discount on a draft
// @Description  Pass a code, or an ad-hoc paise amount with a reason. Empty body clears.
// @Tags         invoicing
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                    true  "Invoice ID"
// @Param        body  body      ApplyDiscountRequest   true  "Discount"
// @Success      200   {object}  InvoiceResponse
// @Failure      409   {object}  response.Envelope  "Discount expired, inactive or exhausted"
// @Router       /api/v1/invoices/{id}/discount [post]
func (h *Handler) ApplyDiscount(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	var req ApplyDiscountRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.ApplyDiscount(r.Context(), id, req)
	if err != nil {
		writeErr(w, err, "apply discount")
		return
	}
	response.OK(w, res)
}

// Issue godoc
// @Summary      Issue a draft invoice
// @Description  Assigns a gapless per-financial-year number. The invoice becomes immutable.
// @Tags         invoicing
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                  true  "Invoice ID"
// @Param        body  body      IssueInvoiceRequest  false "Invoice date"
// @Success      200   {object}  InvoiceResponse
// @Failure      409   {object}  response.Envelope  "Already issued, or has no line items"
// @Router       /api/v1/invoices/{id}/issue [post]
func (h *Handler) Issue(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	var req IssueInvoiceRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.Issue(r.Context(), id, req)
	if err != nil {
		writeErr(w, err, "issue invoice")
		return
	}
	response.OK(w, res)
}

// Cancel godoc
// @Summary      Cancel an issued invoice
// @Description  The number is retained and never reused. A reason is required.
// @Tags         invoicing
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                   true  "Invoice ID"
// @Param        body  body      CancelInvoiceRequest  true  "Reason"
// @Success      200   {object}  InvoiceResponse
// @Failure      422   {object}  response.Envelope  "Reason missing"
// @Router       /api/v1/invoices/{id}/cancel [post]
func (h *Handler) Cancel(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	var req CancelInvoiceRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.Cancel(r.Context(), id, req)
	if err != nil {
		writeErr(w, err, "cancel invoice")
		return
	}
	response.OK(w, res)
}

// ─── Discounts ────────────────────────────────────────────────────────────────

// CreateDiscount godoc
// @Summary      Create a discount rule
// @Tags         invoicing
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      CreateDiscountRequest  true  "Discount"
// @Success      201   {object}  DiscountResponse
// @Failure      409   {object}  response.Envelope  "Code already exists"
// @Router       /api/v1/discounts [post]
func (h *Handler) CreateDiscount(w http.ResponseWriter, r *http.Request) {
	var req CreateDiscountRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.CreateDiscount(r.Context(), req)
	if err != nil {
		writeErr(w, err, "create discount")
		return
	}
	response.Created(w, res)
}

// ListDiscounts godoc
// @Summary      List discount rules
// @Tags         invoicing
// @Produce      json
// @Security     BearerAuth
// @Param        active_only  query     bool  false  "Only active discounts"
// @Success      200          {array}   DiscountResponse
// @Router       /api/v1/discounts [get]
func (h *Handler) ListDiscounts(w http.ResponseWriter, r *http.Request) {
	activeOnly := r.URL.Query().Get("active_only") == "true"
	res, err := h.svc.ListDiscounts(r.Context(), activeOnly)
	if err != nil {
		writeErr(w, err, "list discounts")
		return
	}
	response.OK(w, res)
}

// UpdateDiscount godoc
// @Summary      Edit a discount rule
// @Description  Never affects invoices already issued with this discount.
// @Tags         invoicing
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                    true  "Discount ID"
// @Param        body  body      UpdateDiscountRequest  true  "Changes"
// @Success      200   {object}  DiscountResponse
// @Router       /api/v1/discounts/{id} [put]
func (h *Handler) UpdateDiscount(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	var req UpdateDiscountRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.UpdateDiscount(r.Context(), id, req)
	if err != nil {
		writeErr(w, err, "update discount")
		return
	}
	response.OK(w, res)
}

// ─── Settings ─────────────────────────────────────────────────────────────────

// GetSettings godoc
// @Summary      This gym's invoicing settings
// @Tags         invoicing
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  BillingSettingsResponse
// @Router       /api/v1/billing-settings [get]
func (h *Handler) GetSettings(w http.ResponseWriter, r *http.Request) {
	res, err := h.svc.GetSettings(r.Context())
	if err != nil {
		writeErr(w, err, "get settings")
		return
	}
	response.OK(w, res)
}

// UpdateSettings godoc
// @Summary      Update invoicing settings
// @Tags         invoicing
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      UpdateBillingSettingsRequest  true  "Settings"
// @Success      200   {object}  BillingSettingsResponse
// @Router       /api/v1/billing-settings [put]
func (h *Handler) UpdateSettings(w http.ResponseWriter, r *http.Request) {
	var req UpdateBillingSettingsRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.UpdateSettings(r.Context(), req)
	if err != nil {
		writeErr(w, err, "update settings")
		return
	}
	response.OK(w, res)
}

// ─── helpers ──────────────────────────────────────────────────────────────────

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
	case errors.Is(err, ErrInvoiceNotFound),
		errors.Is(err, ErrItemNotFound),
		errors.Is(err, ErrDiscountNotFound),
		errors.Is(err, ErrMemberNotFound):
		response.NotFound(w, err.Error())

	case errors.Is(err, ErrInvoiceNotDraft),
		errors.Is(err, ErrInvoiceNotIssued),
		errors.Is(err, ErrInvoiceCancelled),
		errors.Is(err, ErrInvoiceHasNoItems),
		errors.Is(err, ErrDiscountInactive),
		errors.Is(err, ErrDiscountExpired),
		errors.Is(err, ErrDiscountExhausted),
		errors.Is(err, ErrDiscountCodeTaken):
		response.Conflict(w, err.Error())

	case errors.Is(err, ErrDescriptionRequired),
		errors.Is(err, ErrQuantityInvalid),
		errors.Is(err, ErrUnitPriceNegative),
		errors.Is(err, ErrDiscountNegative),
		errors.Is(err, ErrCancelReasonMissing),
		errors.Is(err, ErrDiscountCodeMissing),
		errors.Is(err, ErrDiscountNameMissing),
		errors.Is(err, ErrDiscountValueRange):
		response.UnprocessableEntity(w, err.Error())

	default:
		if isValidationErr(err) {
			response.UnprocessableEntity(w, err.Error())
			return
		}
		log.Printf("invoicing %s: %v", op, err)
		response.InternalServerError(w)
	}
}

func isValidationErr(err error) bool {
	msg := err.Error()
	for _, marker := range []string{
		"invalid date", "must be one of", "must be between", "cannot be empty",
		"cannot be before", "a reason is required", "not found", "greater than 0",
	} {
		if strings.Contains(msg, marker) {
			return true
		}
	}
	return false
}
