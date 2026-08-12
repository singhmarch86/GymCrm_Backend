package queues

import (
	"errors"
	"log"
	"net/http"
	"strconv"

	"gymcrm/internal/shared/response"
)

// Renewals godoc
// @Summary      Memberships expiring inside the 30-day window
// @Description  Lapsed, today, this week, this month. Anything lapsed longer ago is counted but not listed.
// @Tags         queues
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  RenewalQueue
// @Router       /api/v1/queues/renewals [get]
func (h *Handler) Renewals(w http.ResponseWriter, r *http.Request) {
	queue, err := h.svc.Renewals(r.Context())
	if err != nil {
		log.Printf("queues: renewals: %v", err)
		response.InternalServerError(w)
		return
	}
	response.OK(w, queue)
}

type lapseRequest struct {
	Reason string `json:"reason"`
}

// ConfirmLapse godoc
// @Summary      Record that a member did not come back
// @Description  Owner only. Sets the member to churned and writes a lapse_confirmed event with the reason.
// @Tags         queues
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path  int           true  "Member ID"
// @Param        body  body  lapseRequest  true  "Reason"
// @Success      204
// @Router       /api/v1/members/{id}/confirm-lapse [post]
func (h *Handler) ConfirmLapse(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || id <= 0 {
		response.BadRequest(w, "invalid member id")
		return
	}

	var req lapseRequest
	if !decode(w, r, &req) {
		return
	}

	if err := h.svc.ConfirmLapse(r.Context(), id, req.Reason); err != nil {
		switch {
		case errors.Is(err, ErrOwnerOnly):
			response.Forbidden(w, "only an owner can confirm a lapse")
		case errors.Is(err, ErrReasonRequired):
			response.BadRequest(w, "confirming a lapse needs a reason")
		case errors.Is(err, ErrNotLapsable):
			response.BadRequest(w, "that member is already closed")
		default:
			log.Printf("queues: confirm lapse: %v", err)
			response.InternalServerError(w)
		}
		return
	}
	response.NoContent(w)
}
