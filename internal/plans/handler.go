package plans

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"

	"gymcrm/internal/shared/pagination"
	"gymcrm/internal/shared/response"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// RegisterRoutes mounts all plan endpoints.
// All routes require JWT — caller wraps with JWTMiddleware.
func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/plans",            h.Create)
	mux.HandleFunc("GET /api/v1/plans",             h.List)
	mux.HandleFunc("GET /api/v1/plans/active",      h.ListActive)
	mux.HandleFunc("GET /api/v1/plans/{id}",        h.GetByID)
	mux.HandleFunc("PUT /api/v1/plans/{id}",        h.Update)
	mux.HandleFunc("DELETE /api/v1/plans/{id}",     h.Delete)
}

// Create godoc
// @Summary      Create a membership plan
// @Description  Creates a new membership plan for the authenticated gym.
//               Plan names are case-insensitively unique within a gym.
//               "Monthly Basic" and "monthly basic" are treated as the same name.
//               Price must be provided in paise (₹1,500 = 150000 paise).
// @Tags         plans
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      CreatePlanRequest  true  "Plan details"
// @Success      201   {object}  PlanResponse
// @Failure      409   {object}  response.Envelope  "Plan name already exists in this gym"
// @Failure      422   {object}  response.Envelope  "Validation error"
// @Failure      401   {object}  response.Envelope
// @Router       /api/v1/plans [post]
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	var req CreatePlanRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "invalid request body")
		return
	}
	if err := ValidateCreatePlanRequest(&req); err != nil {
		response.UnprocessableEntity(w, err.Error())
		return
	}
	result, err := h.svc.CreatePlan(r.Context(), req)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.Created(w, result)
}

// GetByID godoc
// @Summary      Get plan by ID
// @Description  Returns a single membership plan. Only returns plans belonging to the authenticated gym.
// @Tags         plans
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Plan ID"
// @Success      200  {object}  PlanResponse
// @Failure      404  {object}  response.Envelope
// @Failure      401  {object}  response.Envelope
// @Router       /api/v1/plans/{id} [get]
func (h *Handler) GetByID(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		response.BadRequest(w, "invalid plan id")
		return
	}
	result, err := h.svc.GetPlan(r.Context(), id)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, result)
}

// List godoc
// @Summary      List membership plans
// @Description  Returns a paginated list of plans for the authenticated gym.
//               Filter by active status or search by name.
// @Tags         plans
// @Produce      json
// @Security     BearerAuth
// @Param        page      query  int     false  "Page number (default: 1)"
// @Param        per_page  query  int     false  "Items per page (default: 20, max: 100)"
// @Param        search    query  string  false  "Search by plan name"
// @Param        active    query  bool    false  "Filter by active status (true/false)"
// @Success      200  {object}  PlanListResponse
// @Failure      401  {object}  response.Envelope
// @Router       /api/v1/plans [get]
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	p := pagination.FromRequest(r)
	req := ListPlansRequest{
		Page:    p.Page,
		PerPage: p.PerPage,
		Search:  strings.TrimSpace(r.URL.Query().Get("search")),
	}

	// Parse optional ?active= filter
	if activeStr := r.URL.Query().Get("active"); activeStr != "" {
		active := activeStr == "true"
		req.IsActive = &active
	}

	plans, total, err := h.svc.ListPlans(r.Context(), req)
	if err != nil {
		h.handleError(w, err)
		return
	}

	response.JSONWithMeta(w, http.StatusOK,
		PlanListResponse{Plans: plans},
		pagination.BuildMeta(p, total),
	)
}

// ListActive godoc
// @Summary      List active plans
// @Description  Returns only active, assignable plans for the authenticated gym.
//               Use this endpoint to populate plan selection dropdowns in Flutter.
//               Sorted alphabetically by name.
// @Tags         plans
// @Produce      json
// @Security     BearerAuth
// @Param        page      query  int  false  "Page number"
// @Param        per_page  query  int  false  "Items per page"
// @Success      200  {object}  PlanListResponse
// @Failure      401  {object}  response.Envelope
// @Router       /api/v1/plans/active [get]
func (h *Handler) ListActive(w http.ResponseWriter, r *http.Request) {
	p := pagination.FromRequest(r)
	plans, total, err := h.svc.ListActivePlans(r.Context(), p)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.JSONWithMeta(w, http.StatusOK,
		PlanListResponse{Plans: plans},
		pagination.BuildMeta(p, total),
	)
}

// Update godoc
// @Summary      Update a membership plan
// @Description  Updates plan fields. Only provided fields are changed.
//               Setting is_active=false hides the plan — existing members and
//               renewals referencing this plan are unaffected.
//               gym_id cannot be changed.
// @Tags         plans
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                true  "Plan ID"
// @Param        body  body      UpdatePlanRequest  true  "Fields to update"
// @Success      200   {object}  PlanResponse
// @Failure      404   {object}  response.Envelope
// @Failure      409   {object}  response.Envelope  "Plan name already taken"
// @Failure      422   {object}  response.Envelope
// @Failure      401   {object}  response.Envelope
// @Router       /api/v1/plans/{id} [put]
func (h *Handler) Update(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		response.BadRequest(w, "invalid plan id")
		return
	}
	var req UpdatePlanRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "invalid request body")
		return
	}
	if err := ValidateUpdatePlanRequest(&req); err != nil {
		response.UnprocessableEntity(w, err.Error())
		return
	}
	result, err := h.svc.UpdatePlan(r.Context(), id, req)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, result)
}

// Delete godoc
// @Summary      Delete a plan (soft delete)
// @Description  Soft-deletes a membership plan. The plan is hidden from all queries
//               but existing member and renewal records referencing it are preserved.
//               The plan name becomes available for reuse after deletion.
//               Cannot delete plans from other gyms.
// @Tags         plans
// @Produce      json
// @Security     BearerAuth
// @Param        id  path      int  true  "Plan ID"
// @Success      200  {object}  response.Envelope
// @Failure      404  {object}  response.Envelope
// @Failure      401  {object}  response.Envelope
// @Router       /api/v1/plans/{id} [delete]
func (h *Handler) Delete(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		response.BadRequest(w, "invalid plan id")
		return
	}
	if err := h.svc.DeletePlan(r.Context(), id); err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, map[string]string{"message": "plan deleted successfully"})
}

// ─── Error mapping ────────────────────────────────────────────────────────────

func (h *Handler) handleError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrPlanNotFound):
		response.NotFound(w, "plan not found")
	case errors.Is(err, ErrPlanNameExists):
		response.Conflict(w, "a plan with this name already exists in this gym")
	case errors.Is(err, ErrPlanInactive):
		response.UnprocessableEntity(w, "plan is inactive and cannot be assigned")
	case errors.Is(err, ErrInvalidDuration):
		response.UnprocessableEntity(w, "duration_days must be greater than 0")
	case errors.Is(err, ErrInvalidPrice):
		response.UnprocessableEntity(w, "price_in_paise must be greater than 0")
	default:
		log.Printf("ERROR plans handler: %v", err)
		response.InternalServerError(w)
	}
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

func pathID(r *http.Request, key string) (int64, error) {
	return strconv.ParseInt(r.PathValue(key), 10, 64)
}
