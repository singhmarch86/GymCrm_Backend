package leads

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

func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/leads",                   h.Create)
	mux.HandleFunc("GET /api/v1/leads",                    h.List)
	mux.HandleFunc("GET /api/v1/leads/summary",            h.Summary)
	mux.HandleFunc("GET /api/v1/leads/{id}",               h.GetByID)
	mux.HandleFunc("PUT /api/v1/leads/{id}",               h.Update)
	mux.HandleFunc("PATCH /api/v1/leads/{id}/status",      h.AdvanceStatus)
	mux.HandleFunc("POST /api/v1/leads/{id}/convert",      h.Convert)
	mux.HandleFunc("DELETE /api/v1/leads/{id}",            h.Delete)
}

// Create godoc
// @Summary      Register a new lead
// @Tags         leads
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      CreateLeadRequest  true  "Lead details"
// @Success      201   {object}  LeadResponse
// @Router       /api/v1/leads [post]
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	var req CreateLeadRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "invalid request body")
		return
	}
	if err := ValidateCreateLeadRequest(&req); err != nil {
		response.UnprocessableEntity(w, err.Error())
		return
	}
	result, err := h.svc.CreateLead(r.Context(), req)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.Created(w, result)
}

// GetByID godoc
// @Summary      Get lead by ID
// @Tags         leads
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Lead ID"
// @Success      200  {object}  LeadResponse
// @Router       /api/v1/leads/{id} [get]
func (h *Handler) GetByID(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		response.BadRequest(w, "invalid lead id")
		return
	}
	result, err := h.svc.GetLead(r.Context(), id)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, result)
}

// List godoc
// @Summary      List leads
// @Description  Paginated list. Filter by status, source, or search by name/phone.
// @Tags         leads
// @Produce      json
// @Security     BearerAuth
// @Param        page    query  int     false  "Page"
// @Param        per_page query int     false  "Per page"
// @Param        status  query  string  false  "Pipeline stage"
// @Param        source  query  string  false  "Lead source"
// @Param        search  query  string  false  "Name or phone"
// @Success      200  {object}  LeadListResponse
// @Router       /api/v1/leads [get]
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	p := pagination.FromRequest(r)
	leads, total, err := h.svc.ListPaginated(
		r.Context(), p,
		strings.TrimSpace(r.URL.Query().Get("status")),
		strings.TrimSpace(r.URL.Query().Get("source")),
		strings.TrimSpace(r.URL.Query().Get("search")),
		strings.TrimSpace(r.URL.Query().Get("assigned_to")),
	)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.JSONWithMeta(w, http.StatusOK,
		LeadListResponse{Leads: leads},
		pagination.BuildMeta(p, total),
	)
}

// Summary godoc
// @Summary      Lead dashboard KPIs
// @Tags         leads
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  LeadSummaryResponse
// @Router       /api/v1/leads/summary [get]
func (h *Handler) Summary(w http.ResponseWriter, r *http.Request) {
	result, err := h.svc.GetSummary(r.Context())
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, result)
}

// Update godoc
// @Summary      Update a lead
// @Tags         leads
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                 true  "Lead ID"
// @Param        body  body      UpdateLeadRequest   true  "Fields to update"
// @Success      200   {object}  LeadResponse
// @Router       /api/v1/leads/{id} [put]
func (h *Handler) Update(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		response.BadRequest(w, "invalid lead id")
		return
	}
	var req UpdateLeadRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "invalid request body")
		return
	}
	result, err := h.svc.UpdateLead(r.Context(), id, req)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, result)
}

// AdvanceStatus godoc
// @Summary      Move lead to a new pipeline stage
// @Tags         leads
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                    true  "Lead ID"
// @Param        body  body      AdvanceStatusRequest   true  "Target status"
// @Success      200   {object}  LeadResponse
// @Router       /api/v1/leads/{id}/status [patch]
func (h *Handler) AdvanceStatus(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		response.BadRequest(w, "invalid lead id")
		return
	}
	var req AdvanceStatusRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "invalid request body")
		return
	}
	if err := ValidateAdvanceStatusRequest(&req); err != nil {
		response.UnprocessableEntity(w, err.Error())
		return
	}
	result, err := h.svc.AdvanceStatus(r.Context(), id, req)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, result)
}

// Delete godoc
// @Summary      Delete a lead (soft)
// @Tags         leads
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Lead ID"
// @Success      200  {object}  map[string]string
// @Router       /api/v1/leads/{id} [delete]
func (h *Handler) Delete(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		response.BadRequest(w, "invalid lead id")
		return
	}
	if err := h.svc.DeleteLead(r.Context(), id); err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, map[string]string{"message": "lead deleted successfully"})
}

// Convert godoc
// @Summary      Convert lead to member
// @Description  Single atomic transaction: creates member, collects payment,
//               creates renewal, updates expiry, marks lead as joined.
// @Tags         leads
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                  true  "Lead ID"
// @Param        body  body      ConvertLeadRequest   true  "Member + payment details"
// @Success      201   {object}  ConvertLeadResponse
// @Failure      409   {object}  response.Envelope  "Already converted"
// @Failure      422   {object}  response.Envelope  "Invalid lead status or missing fields"
// @Router       /api/v1/leads/{id}/convert [post]
func (h *Handler) Convert(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		response.BadRequest(w, "invalid lead id")
		return
	}
	var req ConvertLeadRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "invalid request body")
		return
	}
	result, err := h.svc.ConvertToMember(r.Context(), id, req)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.Created(w, result)
}

// ─── Error mapping ────────────────────────────────────────────────────────────

func (h *Handler) handleError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrLeadNotFound):
		response.NotFound(w, "lead not found")
	case errors.Is(err, ErrInvalidSource):
		response.UnprocessableEntity(w, err.Error())
	case errors.Is(err, ErrInvalidStatus):
		response.UnprocessableEntity(w, err.Error())
	case errors.Is(err, ErrInvalidActivityType):
		response.UnprocessableEntity(w, err.Error())
	case errors.Is(err, ErrLostReasonRequired):
		response.UnprocessableEntity(w, err.Error())
	case errors.Is(err, ErrAlreadyConverted):
		response.Conflict(w, err.Error())
	case errors.Is(err, ErrInvalidLeadForConversion):
		response.UnprocessableEntity(w, err.Error())
	default:
		log.Printf("ERROR leads handler: %v", err)
		response.InternalServerError(w)
	}
}

func pathID(r *http.Request, key string) (int64, error) {
	return strconv.ParseInt(r.PathValue(key), 10, 64)
}
