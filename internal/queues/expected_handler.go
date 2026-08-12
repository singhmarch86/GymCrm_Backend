package queues

import (
	"errors"
	"log"
	"net/http"

	"gymcrm/internal/shared/response"
	"gymcrm/internal/staffwork"
)

// Expected godoc
// @Summary      Money the gym has reason to expect over a span of days
// @Description  Two figures, never added together: dues already raised with a due date in the span, and memberships expiring in it valued at today's plan price. Day, month or custom range, same parameters as staff work.
// @Tags         queues
// @Produce      json
// @Security     BearerAuth
// @Param        date  query  string  false  "Single day, YYYY-MM-DD; defaults to today"
// @Param        from  query  string  false  "Range start, YYYY-MM-DD; must be sent with to"
// @Param        to    query  string  false  "Range end, YYYY-MM-DD; must be sent with from"
// @Success      200  {object}  ExpectedPayments
// @Router       /api/v1/queues/expected [get]
func (h *Handler) Expected(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()

	// The same parser staff work uses, so a range that is legal on one screen
	// is legal on the other. A date control that works differently depending
	// on which tab it sits above is a bug the reader has to discover.
	rng, err := staffwork.ParseRange(q.Get("date"), q.Get("from"), q.Get("to"))
	if err != nil {
		switch {
		case errors.Is(err, staffwork.ErrRangeBack):
			response.BadRequest(w, "the end of the range is before the start")
		case errors.Is(err, staffwork.ErrRangeHuge):
			response.BadRequest(w, "that range is longer than a year")
		default:
			response.BadRequest(w, "dates must be YYYY-MM-DD, and from and to go together")
		}
		return
	}

	out, err := h.svc.Expected(r.Context(), rng)
	if err != nil {
		log.Printf("queues: expected: %v", err)
		response.InternalServerError(w)
		return
	}
	response.OK(w, out)
}
