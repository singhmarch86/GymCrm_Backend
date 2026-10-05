package staffwork

import (
	"errors"
	"log"
	"net/http"
	"net/url"
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

	// True when there were more rows than the cap. The client must say so
	// rather than presenting a truncated list as the whole story.
	Truncated bool `json:"truncated"`
	Limit     int  `json:"limit"`
}

// readRange pulls the range out of a query string and turns a parse failure
// into the specific message that names what was wrong.
func readRange(q url.Values) (Range, error) {
	return ParseRange(
		strings.TrimSpace(q.Get("date")),
		strings.TrimSpace(q.Get("from")),
		strings.TrimSpace(q.Get("to")),
	)
}

// rangeError maps a range parse failure to a message the caller can act on.
// "invalid request" would leave somebody guessing which of three things broke.
func rangeError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrRangeBack):
		response.BadRequest(w, "to must not be before from")
	case errors.Is(err, ErrRangeHuge):
		response.BadRequest(w, "range must not be longer than a year")
	case errors.Is(err, ErrBadRange):
		response.BadRequest(w, "from and to must both be given, in YYYY-MM-DD format")
	default:
		response.BadRequest(w, "date must be in YYYY-MM-DD format")
	}
}

// Day godoc
// @Summary      What each staff member did, over a day or a range
// @Tags         staff-work
// @Produce      json
// @Security     BearerAuth
// @Param        date  query  string  false  "YYYY-MM-DD single day, defaults to today (IST)"
// @Param        from  query  string  false  "YYYY-MM-DD, inclusive; must be paired with to"
// @Param        to    query  string  false  "YYYY-MM-DD, inclusive; must be paired with from"
// @Success      200  {object}  DayReport
// @Router       /api/v1/staff-work [get]
func (h *Handler) Day(w http.ResponseWriter, r *http.Request) {
	rng, err := readRange(r.URL.Query())
	if err != nil {
		rangeError(w, err)
		return
	}

	report, err := h.svc.Day(r.Context(), rng)
	if err != nil {
		log.Printf("staffwork: day %s: %v", rng.Label(), err)
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
// @Param        date      query  string  false  "YYYY-MM-DD single day, defaults to today (IST)"
// @Param        from      query  string  false  "YYYY-MM-DD, inclusive"
// @Param        to        query  string  false  "YYYY-MM-DD, inclusive"
// @Param        user_id   query  int     false  "omit for unattributed work"
// @Param        category  query  string  true   "payments | renewals | sales | invoices | retention | leads | lifecycle | wallet"
// @Success      200  {object}  ItemsResponse
// @Router       /api/v1/staff-work/items [get]
func (h *Handler) Items(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()

	rng, err := readRange(q)
	if err != nil {
		rangeError(w, err)
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

	items, truncated, err := h.svc.Items(r.Context(), rng, userID, category)
	if err != nil {
		if errors.Is(err, ErrUnknownCategory) {
			response.BadRequest(w, "unknown category")
			return
		}
		log.Printf("staffwork: items: %v", err)
		response.InternalServerError(w)
		return
	}
	response.OK(w, ItemsResponse{Items: items, Truncated: truncated, Limit: ItemLimit})
}

// LeadWork godoc
// @Summary      Per-person lead workflow — what each staff member is carrying
// @Description  Carrying counts are always "now"; only the funnel is scoped to the range.
// @Tags         staff-work
// @Produce      json
// @Security     BearerAuth
// @Param        date  query  string  false  "YYYY-MM-DD single day, defaults to today (IST)"
// @Param        from  query  string  false  "YYYY-MM-DD, inclusive"
// @Param        to    query  string  false  "YYYY-MM-DD, inclusive"
// @Success      200  {object}  LeadWorkReport
// @Router       /api/v1/staff-work/leads [get]
func (h *Handler) LeadWork(w http.ResponseWriter, r *http.Request) {
	rng, err := readRange(r.URL.Query())
	if err != nil {
		rangeError(w, err)
		return
	}

	report, err := h.svc.LeadWork(r.Context(), rng)
	if err != nil {
		log.Printf("staffwork: lead work %s: %v", rng.Label(), err)
		response.InternalServerError(w)
		return
	}
	response.OK(w, report)
}

// Analytics godoc
// @Summary      How the desk's workload has moved over a span
// @Description  The gym's rhythm, which ledgers carry the work, quiet days, and each person against their OWN previous period. Deliberately not a ranking — people come back ordered by name, with no score and no comparison between them (FR-13 §1).
// @Tags         staff-work
// @Produce      json
// @Security     BearerAuth
// @Param        date  query  string  false  "Single day, YYYY-MM-DD"
// @Param        from  query  string  false  "Range start, YYYY-MM-DD"
// @Param        to    query  string  false  "Range end, YYYY-MM-DD"
// @Success      200  {object}  StaffAnalytics
// @Router       /api/v1/staff-work/analytics [get]
func (h *Handler) Analytics(w http.ResponseWriter, r *http.Request) {
	rng, err := readRange(r.URL.Query())
	if err != nil {
		rangeError(w, err)
		return
	}

	out, err := h.svc.Analytics(r.Context(), rng)
	if err != nil {
		log.Printf("staffwork: analytics %s: %v", rng.Label(), err)
		response.InternalServerError(w)
		return
	}
	response.OK(w, out)
}
