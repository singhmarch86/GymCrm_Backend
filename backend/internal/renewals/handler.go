package renewals

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

// RegisterRoutes mounts all renewal endpoints.
// All routes require JWT — caller wraps with JWTMiddleware.
func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/renewals", h.Create)
	mux.HandleFunc("GET /api/v1/renewals", h.List)
	mux.HandleFunc("GET /api/v1/renewals/recent", h.Recent)
	mux.HandleFunc("GET /api/v1/renewals/{id}", h.GetByID)
	mux.HandleFunc("GET /api/v1/members/{member_id}/renewals", h.MemberRenewals)
}

// Create godoc
// @Summary      Create a renewal
// @Description  Creates a renewal for a member. Extends their expiry date using:
//
//	new_expiry = max(current_expiry, today) + plan.duration_days
//	Also updates member.expiry_date and sets status to active.
//	gym_id and renewed_by_user_id come from JWT — never from payload.
//
// @Tags         renewals
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      CreateRenewalRequest  true  "Renewal details"
// @Success      201   {object}  RenewalResponse
// @Failure      404   {object}  response.Envelope  "Member or plan not found"
// @Failure      422   {object}  response.Envelope  "Validation error or plan inactive"
// @Failure      401   {object}  response.Envelope
// @Router       /api/v1/renewals [post]
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	var req CreateRenewalRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "invalid request body")
		return
	}
	if err := ValidateCreateRenewalRequest(&req); err != nil {
		response.UnprocessableEntity(w, err.Error())
		return
	}
	result, err := h.svc.CreateRenewal(r.Context(), req)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.Created(w, result)
}

// GetByID godoc
// @Summary      Get renewal by ID
// @Description  Returns a single renewal record with member and plan details.
//
//	Only returns renewals belonging to the authenticated gym.
//
// @Tags         renewals
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Renewal ID"
// @Success      200  {object}  RenewalResponse
// @Failure      404  {object}  response.Envelope
// @Failure      401  {object}  response.Envelope
// @Router       /api/v1/renewals/{id} [get]
func (h *Handler) GetByID(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		response.BadRequest(w, "invalid renewal id")
		return
	}
	result, err := h.svc.GetRenewal(r.Context(), id)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, result)
}

// List godoc
// @Summary      List renewals
// @Description  Returns a paginated list of renewals for the authenticated gym.
//
//	Supports filtering by member_id, plan_id, and date range.
//
// @Tags         renewals
// @Produce      json
// @Security     BearerAuth
// @Param        page        query  int     false  "Page number (default: 1)"
// @Param        per_page    query  int     false  "Items per page (default: 20, max: 100)"
// @Param        member_id   query  int     false  "Filter by member ID"
// @Param        plan_id     query  int     false  "Filter by plan ID"
// @Param        date_from   query  string  false  "Filter from date (YYYY-MM-DD)"
// @Param        date_to     query  string  false  "Filter to date (YYYY-MM-DD)"
// @Success      200  {object}  RenewalListResponse
// @Failure      401  {object}  response.Envelope
// @Router       /api/v1/renewals [get]
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	p := pagination.FromRequest(r)
	req := ListRenewalsRequest{
		Page:    p.Page,
		PerPage: p.PerPage,
	}

	if raw := r.URL.Query().Get("member_id"); raw != "" {
		if id, err := strconv.ParseInt(raw, 10, 64); err == nil {
			req.MemberID = &id
		}
	}
	if raw := r.URL.Query().Get("plan_id"); raw != "" {
		if id, err := strconv.ParseInt(raw, 10, 64); err == nil {
			req.PlanID = &id
		}
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

	renewals, total, err := h.svc.ListRenewals(r.Context(), req)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.JSONWithMeta(w, http.StatusOK,
		RenewalListResponse{Renewals: renewals},
		pagination.BuildMeta(p, total),
	)
}

// MemberRenewals godoc
// @Summary      Get renewal history for a member
// @Description  Returns all renewals for a specific member, sorted by date descending.
//
//	Returns 404 if the member doesn't belong to the authenticated gym.
//
// @Tags         renewals
// @Produce      json
// @Security     BearerAuth
// @Param        member_id  path   int  true   "Member ID"
// @Param        page       query  int  false  "Page number"
// @Param        per_page   query  int  false  "Items per page"
// @Success      200  {object}  RenewalListResponse
// @Failure      404  {object}  response.Envelope  "Member not found"
// @Failure      401  {object}  response.Envelope
// @Router       /api/v1/members/{member_id}/renewals [get]
func (h *Handler) MemberRenewals(w http.ResponseWriter, r *http.Request) {
	memberID, err := pathID(r, "member_id")
	if err != nil {
		response.BadRequest(w, "invalid member id")
		return
	}
	p := pagination.FromRequest(r)
	renewals, total, err := h.svc.GetMemberRenewals(r.Context(), memberID, p)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.JSONWithMeta(w, http.StatusOK,
		RenewalListResponse{Renewals: renewals},
		pagination.BuildMeta(p, total),
	)
}

// Recent godoc
// @Summary      Get recent renewals
// @Description  Returns the most recent N renewals for the authenticated gym.
//
//	Useful for the owner dashboard activity feed.
//	Default limit: 20. Max: 100.
//
// @Tags         renewals
// @Produce      json
// @Security     BearerAuth
// @Param        limit  query  int  false  "Number of renewals to return (default: 20, max: 100)"
// @Success      200    {object}  RenewalListResponse
// @Failure      401    {object}  response.Envelope
// @Router       /api/v1/renewals/recent [get]
func (h *Handler) Recent(w http.ResponseWriter, r *http.Request) {
	limit := 20
	if raw := r.URL.Query().Get("limit"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 {
			limit = n
		}
	}
	renewals, err := h.svc.GetRecentRenewals(r.Context(), limit)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, RenewalListResponse{Renewals: renewals})
}

// ─── Error mapping ────────────────────────────────────────────────────────────

func (h *Handler) handleError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrRenewalNotFound):
		response.NotFound(w, "renewal not found")
	case errors.Is(err, ErrMemberNotFound):
		response.NotFound(w, "member not found")
	case errors.Is(err, ErrPlanNotFound):
		response.NotFound(w, "plan not found")
	case errors.Is(err, ErrPlanInactive):
		response.UnprocessableEntity(w, "plan is inactive and cannot be used for renewal")
	case errors.Is(err, ErrInvalidAmount):
		response.UnprocessableEntity(w, "amount_paid_in_paise must be greater than 0")
	default:
		log.Printf("ERROR renewals handler: %v", err)
		response.InternalServerError(w)
	}
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

func pathID(r *http.Request, key string) (int64, error) {
	return strconv.ParseInt(r.PathValue(key), 10, 64)
}
