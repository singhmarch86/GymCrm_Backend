package recognition

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"

	"gymcrm/internal/shared/response"
)

type Handler struct{ svc *Service }

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

// Create godoc
// @Summary      Recognize a member
// @Description  Private, owner-curated — always a human reason, never a computed score or rank. signal_type/signal_id, if given, cite the rhythm profile or feedback note the caller looked at.
// @Tags         recognition
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int            true  "Member ID"
// @Param        body  body      CreateRequest  true  "Reason and optional signal citation"
// @Success      201   {object}  Row
// @Router       /api/v1/members/{id}/recognitions [post]
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		response.BadRequest(w, "invalid member id")
		return
	}
	var req CreateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "could not read the request")
		return
	}
	out, err := h.svc.Create(r.Context(), id, req)
	if err != nil {
		writeErr(w, err)
		return
	}
	response.Created(w, out)
}

// ByMember godoc
// @Summary      A member's recognition history
// @Description  Private — no score, no rank, just reason + date + who recorded it.
// @Tags         recognition
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Member ID"
// @Success      200  {array}   Row
// @Router       /api/v1/members/{id}/recognitions [get]
func (h *Handler) ByMember(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		response.BadRequest(w, "invalid member id")
		return
	}
	rows, err := h.svc.ByMember(r.Context(), id)
	if err != nil {
		log.Printf("member recognitions: %v", err)
		response.InternalServerError(w)
		return
	}
	response.OK(w, rows)
}

func writeErr(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrBlankReason), errors.Is(err, ErrBadSignal), errors.Is(err, ErrSignalMismatch):
		response.BadRequest(w, err.Error())
	case errors.Is(err, ErrMemberNotHere):
		response.NotFound(w, err.Error())
	default:
		log.Printf("recognition: %v", err)
		response.InternalServerError(w)
	}
}
