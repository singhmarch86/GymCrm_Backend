package visitors

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
	mux.HandleFunc("POST /api/v1/visitors/check-in", h.CheckIn)
	mux.HandleFunc("POST /api/v1/visitors/{id}/check-out", h.CheckOut)
	mux.HandleFunc("POST /api/v1/visitors/{id}/convert-to-lead", h.ConvertToLead)
	mux.HandleFunc("GET /api/v1/visitors", h.List)
}

// CheckIn godoc
// @Summary      Check in a walk-in visitor
// @Tags         visitors
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      CheckInRequest  true  "Visitor details"
// @Success      201   {object}  VisitorResponse
// @Failure      422   {object}  response.Envelope
// @Router       /api/v1/visitors/check-in [post]
func (h *Handler) CheckIn(w http.ResponseWriter, r *http.Request) {
	var req CheckInRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.CheckIn(r.Context(), req)
	if err != nil {
		writeErr(w, err, "check in")
		return
	}
	response.Created(w, res)
}

// CheckOut godoc
// @Summary      Check out a visitor
// @Tags         visitors
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Visitor ID"
// @Success      200  {object}  VisitorResponse
// @Failure      404  {object}  response.Envelope
// @Failure      409  {object}  response.Envelope  "Already checked out"
// @Router       /api/v1/visitors/{id}/check-out [post]
func (h *Handler) CheckOut(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	res, err := h.svc.CheckOut(r.Context(), id)
	if err != nil {
		writeErr(w, err, "check out")
		return
	}
	response.OK(w, res)
}

// ConvertToLead godoc
// @Summary      Convert a visit into a lead
// @Description  Explicit only — nothing converts automatically. source is always "walk_in".
// @Tags         visitors
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                    true  "Visitor ID"
// @Param        body  body      ConvertToLeadRequest   false "Extra lead fields"
// @Success      200   {object}  VisitorResponse
// @Failure      404   {object}  response.Envelope
// @Failure      409   {object}  response.Envelope  "Already converted"
// @Router       /api/v1/visitors/{id}/convert-to-lead [post]
func (h *Handler) ConvertToLead(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var req ConvertToLeadRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.ConvertToLead(r.Context(), id, req)
	if err != nil {
		writeErr(w, err, "convert to lead")
		return
	}
	response.OK(w, res)
}

// List godoc
// @Summary      List visits in a date range
// @Tags         visitors
// @Produce      json
// @Security     BearerAuth
// @Param        from  query     string  false  "YYYY-MM-DD, defaults to today"
// @Param        to    query     string  false  "YYYY-MM-DD, defaults to today"
// @Success      200  {array}   VisitorResponse
// @Router       /api/v1/visitors [get]
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	from, err := parseDateOrToday(r.URL.Query().Get("from"))
	if err != nil {
		response.BadRequest(w, err.Error())
		return
	}
	to := from
	if raw := r.URL.Query().Get("to"); raw != "" {
		to, err = parseDateOrToday(raw)
		if err != nil {
			response.BadRequest(w, err.Error())
			return
		}
	}
	// Inclusive of the whole "to" day.
	to = to.Add(24*time.Hour - time.Nanosecond)

	res, err := h.svc.List(r.Context(), from, to)
	if err != nil {
		writeErr(w, err, "list visitors")
		return
	}
	response.OK(w, res)
}

func pathID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || id <= 0 {
		response.BadRequest(w, "invalid id")
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

func parseDateOrToday(s string) (time.Time, error) {
	if strings.TrimSpace(s) == "" {
		n := time.Now().UTC()
		return time.Date(n.Year(), n.Month(), n.Day(), 0, 0, 0, 0, time.UTC), nil
	}
	t, err := time.Parse("2006-01-02", strings.TrimSpace(s))
	if err != nil {
		return time.Time{}, err
	}
	return t, nil
}

func writeErr(w http.ResponseWriter, err error, op string) {
	switch {
	case errors.Is(err, ErrVisitorNotFound):
		response.NotFound(w, err.Error())
	case errors.Is(err, ErrAlreadyCheckedOut), errors.Is(err, ErrAlreadyConverted):
		response.Conflict(w, err.Error())
	case errors.Is(err, ErrInvalidPurpose), errors.Is(err, ErrNameRequired):
		response.UnprocessableEntity(w, err.Error())
	default:
		log.Printf("visitors %s: %v", op, err)
		response.InternalServerError(w)
	}
}
