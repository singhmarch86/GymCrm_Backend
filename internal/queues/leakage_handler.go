package queues

import (
	"log"
	"net/http"

	"gymcrm/internal/shared/response"
)

// Leakage godoc
// @Summary      Value the gym handed over without billing it
// @Description  Sessions delivered beyond a package's limit, members training after expiry, and package counters that disagree with their bookings. Findings, not accusations — nothing here charges anybody.
// @Tags         queues
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  LeakageReport
// @Router       /api/v1/queues/leakage [get]
func (h *Handler) Leakage(w http.ResponseWriter, r *http.Request) {
	out, err := h.svc.Leakage(r.Context())
	if err != nil {
		log.Printf("queues: leakage: %v", err)
		response.InternalServerError(w)
		return
	}
	response.OK(w, out)
}
