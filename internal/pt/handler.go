package pt

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"gymcrm/internal/shared/response"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/pt-packages", h.CreatePackage)
	mux.HandleFunc("GET /api/v1/pt-packages", h.ListPackages)
	mux.HandleFunc("PATCH /api/v1/pt-packages/{id}/status", h.UpdatePackageStatus)
	mux.HandleFunc("GET /api/v1/members/{member_id}/pt-packages", h.MemberPackages)

	mux.HandleFunc("POST /api/v1/pt-appointments", h.Book)
	mux.HandleFunc("GET /api/v1/pt-appointments", h.ListAppointments)
	mux.HandleFunc("POST /api/v1/pt-appointments/{id}/outcome", h.SetOutcome)
}

// CreatePackage godoc
// @Summary      Sell a PT package
// @Tags         pt
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      CreatePackageRequest  true  "Package details"
// @Success      201   {object}  PackageResponse
// @Failure      422   {object}  response.Envelope
// @Router       /api/v1/pt-packages [post]
func (h *Handler) CreatePackage(w http.ResponseWriter, r *http.Request) {
	var req CreatePackageRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.CreatePackage(r.Context(), req)
	if err != nil {
		writeErr(w, err, "create package")
		return
	}
	response.Created(w, res)
}

// ListPackages godoc
// @Summary      List PT packages
// @Tags         pt
// @Produce      json
// @Security     BearerAuth
// @Param        trainer_id  query     int  false  "Filter by trainer"
// @Success      200  {array}   PackageResponse
// @Router       /api/v1/pt-packages [get]
func (h *Handler) ListPackages(w http.ResponseWriter, r *http.Request) {
	var trainerID *int64
	if raw := r.URL.Query().Get("trainer_id"); raw != "" {
		id, err := strconv.ParseInt(raw, 10, 64)
		if err != nil {
			response.BadRequest(w, "invalid trainer_id")
			return
		}
		trainerID = &id
	}
	res, err := h.svc.ListPackages(r.Context(), nil, trainerID)
	if err != nil {
		writeErr(w, err, "list packages")
		return
	}
	response.OK(w, res)
}

// MemberPackages godoc
// @Summary      A member's PT packages
// @Tags         pt
// @Produce      json
// @Security     BearerAuth
// @Param        member_id  path      int  true  "Member ID"
// @Success      200  {array}   PackageResponse
// @Router       /api/v1/members/{member_id}/pt-packages [get]
func (h *Handler) MemberPackages(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "member_id")
	if !ok {
		return
	}
	res, err := h.svc.ListPackages(r.Context(), &id, nil)
	if err != nil {
		writeErr(w, err, "list member packages")
		return
	}
	response.OK(w, res)
}

// UpdatePackageStatus godoc
// @Summary      Change a package's status
// @Tags         pt
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                          true  "Package ID"
// @Param        body  body      UpdatePackageStatusRequest   true  "New status"
// @Success      200   {object}  PackageResponse
// @Failure      404   {object}  response.Envelope
// @Router       /api/v1/pt-packages/{id}/status [patch]
func (h *Handler) UpdatePackageStatus(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	var req UpdatePackageStatusRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.UpdatePackageStatus(r.Context(), id, req)
	if err != nil {
		writeErr(w, err, "update package status")
		return
	}
	response.OK(w, res)
}

// Book godoc
// @Summary      Book a PT appointment
// @Description  Does not consume a session credit — completing it does.
// @Tags         pt
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      CreateAppointmentRequest  true  "Appointment details"
// @Success      201   {object}  AppointmentResponse
// @Failure      404   {object}  response.Envelope  "Package not found"
// @Failure      409   {object}  response.Envelope  "Package not active"
// @Router       /api/v1/pt-appointments [post]
func (h *Handler) Book(w http.ResponseWriter, r *http.Request) {
	var req CreateAppointmentRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.Book(r.Context(), req)
	if err != nil {
		writeErr(w, err, "book appointment")
		return
	}
	response.Created(w, res)
}

// ListAppointments godoc
// @Summary      List PT appointments in a date range
// @Tags         pt
// @Produce      json
// @Security     BearerAuth
// @Param        from        query     string  false  "RFC3339, defaults to today"
// @Param        to          query     string  false  "RFC3339, defaults to 7 days later"
// @Param        trainer_id  query     int     false  "Filter by trainer"
// @Success      200  {array}   AppointmentResponse
// @Router       /api/v1/pt-appointments [get]
func (h *Handler) ListAppointments(w http.ResponseWriter, r *http.Request) {
	from, err := parseTimeOrDefault(r.URL.Query().Get("from"), time.Now().UTC().Truncate(24*time.Hour))
	if err != nil {
		response.BadRequest(w, err.Error())
		return
	}
	to, err := parseTimeOrDefault(r.URL.Query().Get("to"), from.Add(7*24*time.Hour))
	if err != nil {
		response.BadRequest(w, err.Error())
		return
	}
	var trainerID *int64
	if raw := r.URL.Query().Get("trainer_id"); raw != "" {
		id, err := strconv.ParseInt(raw, 10, 64)
		if err != nil {
			response.BadRequest(w, "invalid trainer_id")
			return
		}
		trainerID = &id
	}
	res, err := h.svc.ListAppointments(r.Context(), from, to, trainerID, nil)
	if err != nil {
		writeErr(w, err, "list appointments")
		return
	}
	response.OK(w, res)
}

// SetOutcome godoc
// @Summary      Set an appointment's outcome
// @Description  Only 'completed' consumes a session credit from the linked package.
// @Tags         pt
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                      true  "Appointment ID"
// @Param        body  body      MarkAttendanceRequest    true  "completed | cancelled | no_show"
// @Success      200   {object}  AppointmentResponse
// @Failure      404   {object}  response.Envelope
// @Failure      409   {object}  response.Envelope  "Not scheduled, or package exhausted"
// @Router       /api/v1/pt-appointments/{id}/outcome [post]
func (h *Handler) SetOutcome(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	var req MarkAttendanceRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.SetOutcome(r.Context(), id, req)
	if err != nil {
		writeErr(w, err, "set outcome")
		return
	}
	response.OK(w, res)
}

func pathID(w http.ResponseWriter, r *http.Request, param string) (int64, bool) {
	id, err := strconv.ParseInt(r.PathValue(param), 10, 64)
	if err != nil || id <= 0 {
		response.BadRequest(w, "invalid "+param)
		return 0, false
	}
	return id, true
}

func decode(w http.ResponseWriter, r *http.Request, dst any) bool {
	if r.Body == nil || r.ContentLength == 0 {
		return true
	}
	if err := json.NewDecoder(r.Body).Decode(dst); err != nil {
		response.BadRequest(w, "invalid request body")
		return false
	}
	return true
}

func parseTimeOrDefault(s string, def time.Time) (time.Time, error) {
	if strings.TrimSpace(s) == "" {
		return def, nil
	}
	return time.Parse(time.RFC3339, strings.TrimSpace(s))
}

func writeErr(w http.ResponseWriter, err error, op string) {
	switch {
	case errors.Is(err, ErrPackageNotFound),
		errors.Is(err, ErrTrainerNotFound),
		errors.Is(err, ErrMemberNotFound),
		errors.Is(err, ErrAppointmentNotFound):
		response.NotFound(w, err.Error())
	case errors.Is(err, ErrPackageNotActive),
		errors.Is(err, ErrPackageExhausted),
		errors.Is(err, ErrAppointmentNotScheduled):
		response.Conflict(w, err.Error())
	case errors.Is(err, ErrPackageNameRequired),
		errors.Is(err, ErrTotalSessionsRequired),
		errors.Is(err, ErrAmountNegative),
		// Taking more than the package costs is somebody mistyping, not the
		// server failing. It was returning a 500, which tells the desk to
		// call support about their own typo.
		errors.Is(err, ErrBadPaidAmount),
		errors.Is(err, ErrScheduledAtRequired):
		response.UnprocessableEntity(w, err.Error())
	default:
		if isValidationErr(err) {
			response.UnprocessableEntity(w, err.Error())
			return
		}
		log.Printf("pt %s: %v", op, err)
		response.InternalServerError(w)
	}
}

func isValidationErr(err error) bool {
	msg := err.Error()
	for _, marker := range []string{"invalid ", "must be one of", "expected YYYY-MM-DD", "expected RFC3339"} {
		if strings.Contains(msg, marker) {
			return true
		}
	}
	return false
}
