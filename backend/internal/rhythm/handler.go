package rhythm

import (
	"errors"
	"log"
	"net/http"
	"strconv"

	"gymcrm/internal/shared/response"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

// BreakListResponse wraps the open rhythm-break list.
type BreakListResponse struct {
	Breaks []BreakRow `json:"breaks"`
}

// Scan godoc
// @Summary      Detect members whose training rhythm has broken
// @Description  Analyses check-in timestamps: flags members who have stopped keeping their usual time slot while still attending as often as before.
// @Tags         rhythm
// @Produce      json
// @Security     BearerAuth
// @Param        as_of  query  string  false  "Evaluate as of this date (YYYY-MM-DD), defaults to today"
// @Success      200  {object}  ScanResult
// @Router       /api/v1/rhythm/scan [post]
func (h *Handler) Scan(w http.ResponseWriter, r *http.Request) {
	result, err := h.svc.Scan(r.Context(), r.URL.Query().Get("as_of"))
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, result)
}

// ListBreaks godoc
// @Summary      List open rhythm-break alerts with the numbers behind them
// @Tags         rhythm
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  BreakListResponse
// @Router       /api/v1/rhythm/breaks [get]
func (h *Handler) ListBreaks(w http.ResponseWriter, r *http.Request) {
	rows, err := h.svc.ListBreaks(r.Context())
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, BreakListResponse{Breaks: rows})
}

// GetProfile godoc
// @Summary      One member's training rhythm, broken or not
// @Tags         rhythm
// @Produce      json
// @Security     BearerAuth
// @Param        id  path  int  true  "Member ID"
// @Success      200  {object}  ProfileRow
// @Failure      404  {object}  response.Envelope
// @Router       /api/v1/rhythm/members/{id} [get]
func (h *Handler) GetProfile(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || id <= 0 {
		response.BadRequest(w, "invalid member id")
		return
	}
	profile, err := h.svc.GetProfile(r.Context(), id)
	if err != nil {
		h.handleError(w, err)
		return
	}
	if profile == nil {
		// Not an error: most members simply do not have enough history for a
		// rhythm to be describable.
		response.NotFound(w, "no rhythm profile for this member yet")
		return
	}
	response.OK(w, profile)
}

func (h *Handler) handleError(w http.ResponseWriter, err error) {
	if errors.Is(err, ErrBadAsOf) {
		response.BadRequest(w, err.Error())
		return
	}
	log.Printf("rhythm: %v", err)
	response.InternalServerError(w)
}
