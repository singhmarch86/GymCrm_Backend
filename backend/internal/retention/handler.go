package retention

import (
	"encoding/json"
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

// ResolveRequest is the optional payload for resolving an alert.
type ResolveRequest struct {
	ActionNote *string `json:"action_note,omitempty"`
}

// StaffActivityResponse wraps the per-staff resolution counts.
type StaffActivityResponse struct {
	Staff []StaffActivity `json:"staff"`
	Days  int             `json:"days"`
}

// AlertListResponse wraps the alert list.
type AlertListResponse struct {
	Alerts []AlertRow `json:"alerts"`
}

// Scan godoc
// @Summary      Run the retention scan (raise new alerts, close stale ones)
// @Tags         retention
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  ScanResult
// @Router       /api/v1/retention/scan [post]
func (h *Handler) Scan(w http.ResponseWriter, r *http.Request) {
	result, err := h.svc.Scan(r.Context())
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, result)
}

// ListAlerts godoc
// @Summary      List retention alerts, most severe first
// @Tags         retention
// @Produce      json
// @Security     BearerAuth
// @Param        severity  query  string  false  "low | medium | high"
// @Param        resolved  query  bool    false  "include resolved alerts"
// @Success      200  {object}  AlertListResponse
// @Router       /api/v1/retention/alerts [get]
func (h *Handler) ListAlerts(w http.ResponseWriter, r *http.Request) {
	severity := strings.TrimSpace(r.URL.Query().Get("severity"))
	includeResolved := r.URL.Query().Get("resolved") == "true"

	alerts, err := h.svc.ListAlerts(r.Context(), severity, includeResolved)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, AlertListResponse{Alerts: alerts})
}

// Resolve godoc
// @Summary      Mark an alert as handled
// @Tags         retention
// @Produce      json
// @Security     BearerAuth
// @Param        id  path  int  true  "Alert ID"
// @Success      204
// @Router       /api/v1/retention/alerts/{id}/resolve [patch]
func (h *Handler) Resolve(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		response.BadRequest(w, "invalid alert id")
		return
	}
	// Body is optional: a bare PATCH with no payload resolves without a note.
	var body ResolveRequest
	if r.Body != nil {
		_ = json.NewDecoder(r.Body).Decode(&body)
	}

	if err := h.svc.ResolveAlert(r.Context(), id, body.ActionNote); err != nil {
		h.handleError(w, err)
		return
	}
	response.NoContent(w)
}

// Summary godoc
// @Summary      Open alert counts by severity, plus last scan time
// @Tags         retention
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  Summary
// @Router       /api/v1/retention/summary [get]
func (h *Handler) Summary(w http.ResponseWriter, r *http.Request) {
	result, err := h.svc.GetSummary(r.Context())
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, result)
}

// StaffActivity godoc
// @Summary      Who has been clearing at-risk alerts
// @Tags         retention
// @Produce      json
// @Security     BearerAuth
// @Param        days  query  int  false  "look-back window, default 7"
// @Success      200  {object}  StaffActivityResponse
// @Router       /api/v1/retention/staff-activity [get]
func (h *Handler) StaffActivity(w http.ResponseWriter, r *http.Request) {
	days := 7
	if v := r.URL.Query().Get("days"); v != "" {
		if parsed, err := strconv.Atoi(v); err == nil && parsed > 0 {
			days = parsed
		}
	}
	items, err := h.svc.StaffActivitySince(r.Context(), days)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, StaffActivityResponse{Staff: items, Days: days})
}

func (h *Handler) handleError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrAlertNotFound):
		response.NotFound(w, err.Error())
	case errors.Is(err, ErrInvalidSeverity):
		response.UnprocessableEntity(w, err.Error())
	default:
		log.Printf("ERROR retention handler: %v", err)
		response.InternalServerError(w)
	}
}
