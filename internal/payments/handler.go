package payments

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"gymcrm/internal/shared/pagination"
	"gymcrm/internal/shared/response"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// RegisterRoutes mounts all payment endpoints.
// All routes require JWT — caller wraps with JWTMiddleware before mounting.
func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/payments",                  h.Collect)
	mux.HandleFunc("GET /api/v1/payments",                   h.List)
	mux.HandleFunc("GET /api/v1/payments/summary",            h.Summary)
	mux.HandleFunc("GET /api/v1/payments/{id}",               h.GetByID)
	mux.HandleFunc("GET /api/v1/members/{member_id}/payments", h.MemberPayments)
}

// Collect godoc
// @Summary      Collect a payment
// @Description  Records a payment and, in the SAME atomic transaction, creates
//               the corresponding renewal and updates the member's expiry date.
//               One click, one transaction — either everything succeeds or
//               nothing is written.
// @Tags         payments
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      CollectPaymentRequest  true  "Payment details"
// @Success      201   {object}  PaymentResponse
// @Failure      404   {object}  response.Envelope  "Member or plan not found"
// @Failure      422   {object}  response.Envelope  "Validation error or plan inactive"
// @Failure      401   {object}  response.Envelope
// @Router       /api/v1/payments [post]
func (h *Handler) Collect(w http.ResponseWriter, r *http.Request) {
	var req CollectPaymentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "invalid request body")
		return
	}
	if err := ValidateCollectPaymentRequest(&req); err != nil {
		response.UnprocessableEntity(w, err.Error())
		return
	}
	result, err := h.svc.CollectPayment(r.Context(), req)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.Created(w, result)
}

// GetByID godoc
// @Summary      Get payment by ID
// @Tags         payments
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Payment ID"
// @Success      200  {object}  PaymentResponse
// @Failure      404  {object}  response.Envelope
// @Router       /api/v1/payments/{id} [get]
func (h *Handler) GetByID(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		response.BadRequest(w, "invalid payment id")
		return
	}
	result, err := h.svc.GetPayment(r.Context(), id)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, result)
}

// List godoc
// @Summary      List payments
// @Description  Paginated list. Filter by status (paid, pending, overdue) and
//               search by member name/phone.
// @Tags         payments
// @Produce      json
// @Security     BearerAuth
// @Param        page      query  int     false  "Page number"
// @Param        per_page  query  int     false  "Items per page"
// @Param        status    query  string  false  "paid | pending | overdue"
// @Param        search    query  string  false  "Search by member name or phone"
// @Param        date_from query  string  false  "YYYY-MM-DD"
// @Param        date_to   query  string  false  "YYYY-MM-DD"
// @Success      200  {object}  PaymentListResponse
// @Router       /api/v1/payments [get]
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	p := pagination.FromRequest(r)
	req := ListPaymentsRequest{
		Page:    p.Page,
		PerPage: p.PerPage,
		Status:  strings.TrimSpace(r.URL.Query().Get("status")),
		Search:  strings.TrimSpace(r.URL.Query().Get("search")),
	}

	if raw := strings.TrimSpace(r.URL.Query().Get("date_from")); raw != "" {
		if t, err := time.Parse("2006-01-02", raw); err == nil {
			req.DateFrom = &t
		}
	}
	if raw := strings.TrimSpace(r.URL.Query().Get("date_to")); raw != "" {
		if t, err := time.Parse("2006-01-02", raw); err == nil {
			req.DateTo = &t
		}
	}

	payments, total, err := h.svc.ListPayments(r.Context(), req)
	if err != nil {
		h.handleError(w, err)
		return
	}

	response.JSONWithMeta(w, http.StatusOK,
		PaymentListResponse{Payments: payments},
		pagination.BuildMeta(p, total),
	)
}

// MemberPayments godoc
// @Summary      Get payment history for a member
// @Tags         payments
// @Produce      json
// @Security     BearerAuth
// @Param        member_id  path   int  true  "Member ID"
// @Param        page       query  int  false  "Page number"
// @Param        per_page   query  int  false  "Items per page"
// @Success      200  {object}  PaymentListResponse
// @Failure      404  {object}  response.Envelope  "Member not found"
// @Router       /api/v1/members/{member_id}/payments [get]
func (h *Handler) MemberPayments(w http.ResponseWriter, r *http.Request) {
	memberID, err := pathID(r, "member_id")
	if err != nil {
		response.BadRequest(w, "invalid member id")
		return
	}
	p := pagination.FromRequest(r)
	payments, total, err := h.svc.GetMemberPayments(r.Context(), memberID, p)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.JSONWithMeta(w, http.StatusOK,
		PaymentListResponse{Payments: payments},
		pagination.BuildMeta(p, total),
	)
}

// Summary godoc
// @Summary      Get revenue summary
// @Description  Today's revenue, this month's revenue, and pending payment
//               count — backs the dashboard Revenue and Payments cards.
// @Tags         payments
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  RevenueSummaryResponse
// @Router       /api/v1/payments/summary [get]
func (h *Handler) Summary(w http.ResponseWriter, r *http.Request) {
	result, err := h.svc.GetRevenueSummary(r.Context())
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, result)
}

// ─── Error mapping ────────────────────────────────────────────────────────────

func (h *Handler) handleError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrMemberNotFound):
		response.NotFound(w, "member not found")
	case errors.Is(err, ErrPlanNotFound):
		response.NotFound(w, "plan not found")
	case errors.Is(err, ErrPlanInactive):
		response.UnprocessableEntity(w, "plan is inactive and cannot be used for a payment")
	case errors.Is(err, ErrPaymentNotFound):
		response.NotFound(w, "payment not found")
	case errors.Is(err, ErrInvalidAmount):
		response.UnprocessableEntity(w, "amount must be greater than 0")
	case errors.Is(err, ErrInvalidPaymentMode):
		response.UnprocessableEntity(w, err.Error())
	default:
		log.Printf("ERROR payments handler: %v", err)
		response.InternalServerError(w)
	}
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

func pathID(r *http.Request, key string) (int64, error) {
	return strconv.ParseInt(r.PathValue(key), 10, 64)
}
