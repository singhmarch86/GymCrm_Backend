package stockreport

import (
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"

	"gymcrm/internal/shared/response"
	"gymcrm/internal/staffwork"
)

type Handler struct{ svc *Service }

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

// Report godoc
// @Summary      What the shop sold, earned, and how long the shelf will last
// @Description  Days of cover per product rather than a fixed reorder level, plus margin, dead stock and a suggested reorder level. Descriptive only — nothing here reorders anything or edits a threshold.
// @Tags         stock
// @Produce      json
// @Security     BearerAuth
// @Param        date  query  string  false  "Single day, YYYY-MM-DD"
// @Param        from  query  string  false  "Window start, YYYY-MM-DD"
// @Param        to    query  string  false  "Window end, YYYY-MM-DD"
// @Param        lead_days  query  int  false  "How long a restock takes; default 7"
// @Success      200  {object}  StockReport
// @Router       /api/v1/stock/analytics [get]
func (h *Handler) Report(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()

	rng, err := staffwork.ParseRange(q.Get("date"), q.Get("from"), q.Get("to"))
	if err != nil {
		switch {
		case errors.Is(err, staffwork.ErrRangeBack):
			response.BadRequest(w, "the end of the window is before the start")
		case errors.Is(err, staffwork.ErrRangeHuge):
			response.BadRequest(w, "that window is longer than a year")
		default:
			response.BadRequest(w,
				"dates must be YYYY-MM-DD, and from and to go together")
		}
		return
	}

	leadDays := 0
	if raw := strings.TrimSpace(q.Get("lead_days")); raw != "" {
		n, convErr := strconv.Atoi(raw)
		if convErr != nil || n < 0 || n > 120 {
			response.BadRequest(w,
				"lead_days must be a number of days between 0 and 120")
			return
		}
		leadDays = n
	}

	out, err := h.svc.Report(r.Context(), rng, leadDays)
	if err != nil {
		log.Printf("stockreport: %v", err)
		response.InternalServerError(w)
		return
	}
	response.OK(w, out)
}
