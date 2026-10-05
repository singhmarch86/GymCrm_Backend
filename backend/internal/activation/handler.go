package activation

import (
	"log"
	"net/http"
	"strconv"

	"gymcrm/internal/shared/response"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

// AlertListResponse wraps the open activation alerts.
type AlertListResponse struct {
	Alerts []AlertRow `json:"alerts"`
}

// FunnelResponse wraps the per-month activation funnel.
type FunnelResponse struct {
	Cohorts []CohortRow `json:"cohorts"`
}

// Scan godoc
// @Summary      Check every member in their first 90 days
// @Description  Raises one alert per new member who has never started, is coming too rarely to form a habit, or has gone quiet — and closes the ones that no longer apply.
// @Tags         activation
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  ScanResult
// @Router       /api/v1/activation/scan [post]
func (h *Handler) Scan(w http.ResponseWriter, r *http.Request) {
	result, err := h.svc.Scan(r.Context())
	if err != nil {
		h.fail(w, err)
		return
	}
	response.OK(w, result)
}

// ListAlerts godoc
// @Summary      Open first-90-days alerts, most urgent first
// @Tags         activation
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  AlertListResponse
// @Router       /api/v1/activation/alerts [get]
func (h *Handler) ListAlerts(w http.ResponseWriter, r *http.Request) {
	rows, err := h.svc.ListAlerts(r.Context())
	if err != nil {
		h.fail(w, err)
		return
	}
	response.OK(w, AlertListResponse{Alerts: rows})
}

// Funnel godoc
// @Summary      Activation funnel by join month
// @Description  For each month's intake: how many ever visited, hit 4 visits in 2 weeks, 12 in a month, and were still coming at days 60-90. No targets are applied — the comparison is this gym against itself.
// @Tags         activation
// @Produce      json
// @Security     BearerAuth
// @Param        months  query  int  false  "How many months back (default 6, max 24)"
// @Success      200  {object}  FunnelResponse
// @Router       /api/v1/activation/funnel [get]
func (h *Handler) Funnel(w http.ResponseWriter, r *http.Request) {
	months := 6
	if raw := r.URL.Query().Get("months"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil {
			months = n
		}
	}
	rows, err := h.svc.Funnel(r.Context(), months)
	if err != nil {
		h.fail(w, err)
		return
	}
	response.OK(w, FunnelResponse{Cohorts: rows})
}

func (h *Handler) fail(w http.ResponseWriter, err error) {
	log.Printf("activation: %v", err)
	response.InternalServerError(w)
}
