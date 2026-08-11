package staffwork

import (
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"

	"gymcrm/internal/shared/response"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// ItemsResponse wraps the drill-down rows.
type ItemsResponse struct {
	Items []Item `json:"items"`
}

// Day godoc
// @Summary      What each staff member did on one day
// @Tags         staff-work
// @Produce      json
// @Security     BearerAuth
// @Param        date  query  string  false  "YYYY-MM-DD, defaults to today (IST)"
// @Success      200  {object}  DayReport
// @Router       /api/v1/staff-work [get]
func (h *Handler) Day(w http.ResponseWriter, r *http.Request) {
	day, err := ParseDay(strings.TrimSpace(r.URL.Query().Get("date")))
	if err != nil {
		response.BadRequest(w, "date must be in YYYY-MM-DD format")
		return
	}

	report, err := h.svc.Day(r.Context(), day)
	if err != nil {
		log.Printf("staffwork: day: %v", err)
		response.InternalServerError(w)
		return
	}
	response.OK(w, report)
}

// Items godoc
// @Summary      The individual rows behind one staff-work number
// @Tags         staff-work
// @Produce      json
// @Security     BearerAuth
// @Param        date      query  string  false  "YYYY-MM-DD, defaults to today (IST)"
// @Param        user_id   query  int     false  "omit for unattributed work"
// @Param        category  query  string  true   "payments | renewals | sales | invoices | retention | leads | lifecycle | wallet"
// @Success      200  {object}  ItemsResponse
// @Router       /api/v1/staff-work/items [get]
func (h *Handler) Items(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()

	day, err := ParseDay(strings.TrimSpace(q.Get("date")))
	if err != nil {
		response.BadRequest(w, "date must be in YYYY-MM-DD format")
		return
	}

	category := Category(strings.TrimSpace(q.Get("category")))
	if !IsValidCategory(string(category)) {
		response.BadRequest(w, "unknown category")
		return
	}

	// Absent user_id means the unattributed bucket — a real query, not a
	// missing parameter, so it must stay distinguishable from a bad one.
	var userID *int64
	if raw := strings.TrimSpace(q.Get("user_id")); raw != "" {
		id, convErr := strconv.ParseInt(raw, 10, 64)
		if convErr != nil || id <= 0 {
			response.BadRequest(w, "user_id must be a positive integer")
			return
		}
		userID = &id
	}

	items, err := h.svc.Items(r.Context(), day, userID, category)
	if err != nil {
		if errors.Is(err, ErrUnknownCategory) {
			response.BadRequest(w, "unknown category")
			return
		}
		log.Printf("staffwork: items: %v", err)
		response.InternalServerError(w)
		return
	}
	response.OK(w, ItemsResponse{Items: items})
}
