package users

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"

	"gymcrm/internal/shared/response"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// List godoc
// @Summary      List gym staff
// @Tags         users
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  StaffListResponse
// @Router       /api/v1/users [get]
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	staff, err := h.svc.ListStaff(r.Context())
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, StaffListResponse{Staff: staff})
}

// Create godoc
// @Summary      Add a staff member
// @Tags         users
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      CreateStaffRequest  true  "Staff details"
// @Success      201   {object}  StaffRow
// @Router       /api/v1/users [post]
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	var req CreateStaffRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "invalid request body")
		return
	}
	result, err := h.svc.CreateStaff(r.Context(), req)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.Created(w, result)
}

// Update godoc
// @Summary      Update a staff member's profile
// @Tags         users
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                 true  "User ID"
// @Param        body  body      UpdateStaffRequest  true  "Fields to change"
// @Success      200   {object}  StaffRow
// @Router       /api/v1/users/{id} [put]
func (h *Handler) Update(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		response.BadRequest(w, "invalid user id")
		return
	}
	var req UpdateStaffRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "invalid request body")
		return
	}
	result, err := h.svc.UpdateStaff(r.Context(), id, req)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, result)
}

// SetStatus godoc
// @Summary      Activate or deactivate a staff member
// @Tags         users
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                  true  "User ID"
// @Param        body  body      UpdateStatusRequest  true  "New status"
// @Success      200   {object}  StaffRow
// @Router       /api/v1/users/{id}/status [patch]
func (h *Handler) SetStatus(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		response.BadRequest(w, "invalid user id")
		return
	}
	var req UpdateStatusRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "invalid request body")
		return
	}
	result, err := h.svc.SetStatus(r.Context(), id, req)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, result)
}

// ResetPassword godoc
// @Summary      Set a new password for a staff member
// @Tags         users
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                    true  "User ID"
// @Param        body  body      ResetPasswordRequest   true  "New password"
// @Success      204
// @Router       /api/v1/users/{id}/password [patch]
func (h *Handler) ResetPassword(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		response.BadRequest(w, "invalid user id")
		return
	}
	var req ResetPasswordRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "invalid request body")
		return
	}
	if err := h.svc.ResetPassword(r.Context(), id, req); err != nil {
		h.handleError(w, err)
		return
	}
	response.NoContent(w)
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

func pathID(r *http.Request, key string) (int64, error) {
	return strconv.ParseInt(r.PathValue(key), 10, 64)
}

func (h *Handler) handleError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrUserNotFound):
		response.NotFound(w, err.Error())
	case errors.Is(err, ErrPhoneTaken):
		response.Conflict(w, err.Error())
	case errors.Is(err, ErrNameRequired),
		errors.Is(err, ErrPhoneRequired),
		errors.Is(err, ErrInvalidRole),
		errors.Is(err, ErrInvalidStatus),
		errors.Is(err, ErrWeakPassword),
		errors.Is(err, ErrLongPassword):
		response.UnprocessableEntity(w, err.Error())
	case errors.Is(err, ErrLastActiveOwner),
		errors.Is(err, ErrCannotDeactivateSelf),
		errors.Is(err, ErrCannotDemoteSelf):
		// Refused on purpose, not a validation slip — 409 reads correctly for
		// "the request is well-formed but would leave the gym in a bad state".
		response.Conflict(w, err.Error())
	default:
		log.Printf("ERROR users handler: %v", err)
		response.InternalServerError(w)
	}
}
