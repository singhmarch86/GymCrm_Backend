package ptreport

import (
	"log"
	"net/http"
	"strconv"

	"gymcrm/internal/shared/response"
)

type Handler struct{ svc *Service }

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

// Member godoc
// @Summary      A member's PT picture
// @Description  Packages bought and remaining, feedback either direction, and their attendance signal — read-only, composed across pt, ptfeedback and rhythm.
// @Tags         pt-reports
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Member ID"
// @Success      200  {object}  MemberReport
// @Router       /api/v1/members/{id}/pt-report [get]
func (h *Handler) Member(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		response.BadRequest(w, "invalid member id")
		return
	}
	out, err := h.svc.Member(r.Context(), id)
	if err != nil {
		log.Printf("member pt report: %v", err)
		response.InternalServerError(w)
		return
	}
	response.OK(w, out)
}

// Trainer godoc
// @Summary      A trainer's PT picture
// @Description  Sessions delivered, feedback given or received, members currently assigned, and last payout — read-only.
// @Tags         pt-reports
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Trainer ID"
// @Success      200  {object}  TrainerReport
// @Router       /api/v1/trainers/{id}/pt-report [get]
func (h *Handler) Trainer(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		response.BadRequest(w, "invalid trainer id")
		return
	}
	out, err := h.svc.Trainer(r.Context(), id)
	if err != nil {
		log.Printf("trainer pt report: %v", err)
		response.InternalServerError(w)
		return
	}
	response.OK(w, out)
}
