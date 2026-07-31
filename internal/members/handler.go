package members

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"

	"gymcrm/internal/renewals"
	"gymcrm/internal/shared/pagination"
	"gymcrm/internal/shared/response"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// RegisterRoutes mounts all member endpoints.
// All routes require JWT — caller wraps with JWTMiddleware before mounting.
//
// Note: GET /api/v1/members/renewals and POST /api/v1/members/{id}/renew
// are registered alongside GET/PUT /api/v1/members/{id}. Go 1.22's ServeMux
// always prefers a more specific literal segment over a wildcard, so
// "/members/renewals" never gets swallowed by "/members/{id}".
func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/members",             h.Create)
	mux.HandleFunc("GET /api/v1/members",              h.List)
	mux.HandleFunc("GET /api/v1/members/search",       h.Search)
	mux.HandleFunc("GET /api/v1/members/expiring",     h.Expiring)
	mux.HandleFunc("GET /api/v1/members/renewals",     h.DueForRenewal)
	mux.HandleFunc("GET /api/v1/members/{id}",         h.GetByID)
	mux.HandleFunc("PUT /api/v1/members/{id}",         h.Update)
	mux.HandleFunc("DELETE /api/v1/members/{id}",      h.Delete)
	mux.HandleFunc("POST /api/v1/members/{id}/renew",  h.Renew)
}

// Create godoc
// @Summary      Add a new member
// @Description  Creates a new member in the authenticated gym. Phone must be unique within the gym.
// @Tags         members
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      CreateMemberRequest  true  "Member details"
// @Success      201   {object}  MemberResponse
// @Failure      409   {object}  response.Envelope  "Phone already registered in this gym"
// @Failure      422   {object}  response.Envelope  "Validation error"
// @Failure      401   {object}  response.Envelope
// @Router       /api/v1/members [post]
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	var req CreateMemberRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "invalid request body")
		return
	}
	if err := ValidateCreateMemberRequest(&req); err != nil {
		response.UnprocessableEntity(w, err.Error())
		return
	}
	result, err := h.svc.CreateMember(r.Context(), req)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.Created(w, result)
}

// GetByID godoc
// @Summary      Get member by ID
// @Description  Returns a single member. Only returns members belonging to the authenticated gym.
// @Tags         members
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Member ID"
// @Success      200  {object}  MemberResponse
// @Failure      404  {object}  response.Envelope
// @Failure      401  {object}  response.Envelope
// @Router       /api/v1/members/{id} [get]
func (h *Handler) GetByID(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		response.BadRequest(w, "invalid member id")
		return
	}
	result, err := h.svc.GetMember(r.Context(), id)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, result)
}

// List godoc
// @Summary      List members
// @Description  Returns a paginated list of members for the authenticated gym.
//               Filter by status or search by name/phone using query parameters.
// @Tags         members
// @Produce      json
// @Security     BearerAuth
// @Param        page      query  int     false  "Page number (default: 1)"
// @Param        per_page  query  int     false  "Items per page (default: 20, max: 100)"
// @Param        status    query  string  false  "Filter by status: active, expired, inactive, churned"
// @Param        search    query  string  false  "Search by first name, last name, or phone"
// @Success      200  {object}  MemberListResponse
// @Failure      401  {object}  response.Envelope
// @Router       /api/v1/members [get]
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	p := pagination.FromRequest(r)
	req := ListMembersRequest{
		Page:    p.Page,
		PerPage: p.PerPage,
		Status:  r.URL.Query().Get("status"),
		Search:  r.URL.Query().Get("search"),
	}

	members, total, err := h.svc.ListMembers(r.Context(), req)
	if err != nil {
		h.handleError(w, err)
		return
	}

	response.JSONWithMeta(w, http.StatusOK,
		MemberListResponse{Members: members},
		pagination.BuildMeta(p, total),
	)
}

// Search godoc
// @Summary      Search members
// @Description  Search members by name or phone within the authenticated gym.
//               Returns empty array for blank query — never returns all members.
// @Tags         members
// @Produce      json
// @Security     BearerAuth
// @Param        q         query  string  true   "Search term (name or phone)"
// @Param        page      query  int     false  "Page number"
// @Param        per_page  query  int     false  "Items per page"
// @Success      200  {object}  MemberListResponse
// @Failure      401  {object}  response.Envelope
// @Router       /api/v1/members/search [get]
func (h *Handler) Search(w http.ResponseWriter, r *http.Request) {
	query := strings.TrimSpace(r.URL.Query().Get("q"))
	p := pagination.FromRequest(r)

	members, total, err := h.svc.SearchMembers(r.Context(), query, p)
	if err != nil {
		h.handleError(w, err)
		return
	}

	response.JSONWithMeta(w, http.StatusOK,
		MemberListResponse{Members: members},
		pagination.BuildMeta(p, total),
	)
}

// Expiring godoc
// @Summary      Get expiring members
// @Description  Returns members whose membership expires within the next N days.
//               Sorted by expiry date ascending (most urgent first).
//               Use this to drive the renewal reminder dashboard.
// @Tags         members
// @Produce      json
// @Security     BearerAuth
// @Param        days      query  int  false  "Days ahead to check (default: 7, max: 90)"
// @Param        page      query  int  false  "Page number"
// @Param        per_page  query  int  false  "Items per page"
// @Success      200  {object}  MemberListResponse
// @Failure      401  {object}  response.Envelope
// @Router       /api/v1/members/expiring [get]
func (h *Handler) Expiring(w http.ResponseWriter, r *http.Request) {
	p := pagination.FromRequest(r)
	days := 7
	if d := r.URL.Query().Get("days"); d != "" {
		if n, err := strconv.Atoi(d); err == nil {
			days = n
		}
	}

	members, total, err := h.svc.GetExpiringMembers(r.Context(), days, p)
	if err != nil {
		h.handleError(w, err)
		return
	}

	response.JSONWithMeta(w, http.StatusOK,
		MemberListResponse{Members: members},
		pagination.BuildMeta(p, total),
	)
}

// Update godoc
// @Summary      Update member
// @Description  Updates member details. Only provided fields are changed (PATCH semantics).
//               gym_id cannot be changed — members always belong to their original gym.
// @Tags         members
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                  true  "Member ID"
// @Param        body  body      UpdateMemberRequest  true  "Fields to update"
// @Success      200   {object}  MemberResponse
// @Failure      404   {object}  response.Envelope
// @Failure      409   {object}  response.Envelope  "Phone already taken"
// @Failure      422   {object}  response.Envelope
// @Failure      401   {object}  response.Envelope
// @Router       /api/v1/members/{id} [put]
func (h *Handler) Update(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		response.BadRequest(w, "invalid member id")
		return
	}
	var req UpdateMemberRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "invalid request body")
		return
	}
	if err := ValidateUpdateMemberRequest(&req); err != nil {
		response.UnprocessableEntity(w, err.Error())
		return
	}
	result, err := h.svc.UpdateMember(r.Context(), id, req)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, result)
}

// Delete godoc
// @Summary      Delete member (soft delete)
// @Description  Soft-deletes a member. The record is retained in the database for audit.
//               Deleted members are excluded from all list and search queries automatically.
//               This action cannot delete members from other gyms — tenant isolation enforced.
// @Tags         members
// @Produce      json
// @Security     BearerAuth
// @Param        id  path      int  true  "Member ID"
// @Success      200  {object}  response.Envelope
// @Failure      404  {object}  response.Envelope
// @Failure      401  {object}  response.Envelope
// @Router       /api/v1/members/{id} [delete]
func (h *Handler) Delete(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		response.BadRequest(w, "invalid member id")
		return
	}
	if err := h.svc.DeleteMember(r.Context(), id); err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, map[string]string{"message": "member deleted successfully"})
}

// DueForRenewal godoc
// @Summary      Get members due for renewal
// @Description  Returns members with an expiry_date set, enriched with plan name,
//               days_remaining, and a computed status bucket (EXPIRED, DUE_TODAY,
//               EXPIRING_SOON, UPCOMING, ACTIVE). Drives the Renewals screen.
// @Tags         members
// @Produce      json
// @Security     BearerAuth
// @Param        filter  query  string  false  "all | today | tomorrow | this_week | expired"
// @Param        search  query  string  false  "Search by member name or phone"
// @Success      200  {object}  RenewalDueListResponse
// @Failure      401  {object}  response.Envelope
// @Router       /api/v1/members/renewals [get]
func (h *Handler) DueForRenewal(w http.ResponseWriter, r *http.Request) {
	filter := RenewalFilter(strings.TrimSpace(r.URL.Query().Get("filter")))
	search := strings.TrimSpace(r.URL.Query().Get("search"))

	results, err := h.svc.GetDueForRenewal(r.Context(), filter, search)
	if err != nil {
		h.handleError(w, err)
		return
	}

	response.OK(w, RenewalDueListResponse{Renewals: results})
}

// Renew godoc
// @Summary      Renew a member's membership
// @Description  Creates a renewal for this member using the given plan. Extends
//               expiry using max(current_expiry, today) + plan.duration_days.
//               Thin wrapper over POST /api/v1/renewals — see that endpoint for
//               the full audit-trail semantics.
// @Tags         members
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                  true  "Member ID"
// @Param        body  body      RenewMemberRequest   true  "Renewal details"
// @Success      200   {object}  MemberResponse
// @Failure      404   {object}  response.Envelope  "Member or plan not found"
// @Failure      422   {object}  response.Envelope  "Validation error or plan inactive"
// @Failure      401   {object}  response.Envelope
// @Router       /api/v1/members/{id}/renew [post]
func (h *Handler) Renew(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		response.BadRequest(w, "invalid member id")
		return
	}

	var req RenewMemberRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "invalid request body")
		return
	}
	if req.PlanID <= 0 {
		response.UnprocessableEntity(w, "plan_id is required")
		return
	}
	if req.AmountPaidInPaise <= 0 {
		response.UnprocessableEntity(w, "amount_paid_in_paise must be greater than 0")
		return
	}

	result, err := h.svc.RenewMember(r.Context(), id, req)
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
	case errors.Is(err, ErrPhoneAlreadyExists):
		response.Conflict(w, "a member with this phone number already exists in this gym")
	case errors.Is(err, ErrInvalidDateRange):
		response.UnprocessableEntity(w, "expiry_date must be after start_date")
	case errors.Is(err, ErrPlanNotFound):
		response.NotFound(w, "membership plan not found")

	// Errors propagated from renewals.Service.CreateRenewal via RenewMember.
	// fmt.Errorf("...: %w", err) preserves the original sentinel for errors.Is.
	case errors.Is(err, renewals.ErrMemberNotFound):
		response.NotFound(w, "member not found")
	case errors.Is(err, renewals.ErrPlanNotFound):
		response.NotFound(w, "plan not found")
	case errors.Is(err, renewals.ErrPlanInactive):
		response.UnprocessableEntity(w, "plan is inactive and cannot be used for renewal")
	case errors.Is(err, renewals.ErrInvalidAmount):
		response.UnprocessableEntity(w, "amount_paid_in_paise must be greater than 0")

	default:
		log.Printf("ERROR members handler: %v", err)
		response.InternalServerError(w)
	}
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

// pathID extracts a numeric path parameter from the request.
// Uses Go 1.22 ServeMux path value extraction.
func pathID(r *http.Request, key string) (int64, error) {
	raw := r.PathValue(key)
	return strconv.ParseInt(raw, 10, 64)
}
