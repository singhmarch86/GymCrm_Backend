package classes

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

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

// RegisterRoutes mounts all classes/booking endpoints.
// All routes require JWT — the caller wraps them with JWTMiddleware.
func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/class-types", h.CreateClassType)
	mux.HandleFunc("GET /api/v1/class-types", h.ListClassTypes)

	mux.HandleFunc("POST /api/v1/class-schedules", h.CreateSchedule)
	mux.HandleFunc("GET /api/v1/class-schedules", h.ListSchedules)
	mux.HandleFunc("POST /api/v1/class-schedules/generate", h.GenerateUpcomingSessions)

	mux.HandleFunc("POST /api/v1/class-sessions", h.CreateAdHocSession)
	mux.HandleFunc("GET /api/v1/class-sessions", h.ListSessions)
	mux.HandleFunc("GET /api/v1/class-sessions/{id}", h.GetSession)
	mux.HandleFunc("PUT /api/v1/class-sessions/{id}", h.UpdateSession)
	mux.HandleFunc("POST /api/v1/class-sessions/{id}/cancel", h.CancelSession)
	mux.HandleFunc("POST /api/v1/class-sessions/{id}/complete", h.CompleteSession)

	mux.HandleFunc("POST /api/v1/class-sessions/{id}/bookings", h.Book)
	mux.HandleFunc("GET /api/v1/class-sessions/{id}/bookings", h.SessionBookings)
	mux.HandleFunc("POST /api/v1/bookings/{id}/cancel", h.CancelBooking)
	mux.HandleFunc("POST /api/v1/bookings/{id}/attendance", h.MarkAttendance)
	mux.HandleFunc("GET /api/v1/members/{member_id}/bookings", h.MemberBookings)
}

// ─── Class types ──────────────────────────────────────────────────────────────

// CreateClassType godoc
// @Summary      Create a class type
// @Description  Creates a class offering (Yoga, Zumba). gym_id comes from JWT.
// @Tags         classes
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      CreateClassTypeRequest  true  "Class type details"
// @Success      201   {object}  ClassTypeResponse
// @Failure      422   {object}  response.Envelope
// @Router       /api/v1/class-types [post]
func (h *Handler) CreateClassType(w http.ResponseWriter, r *http.Request) {
	var req CreateClassTypeRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.CreateClassType(r.Context(), req)
	if err != nil {
		writeErr(w, err, "create class type")
		return
	}
	response.Created(w, res)
}

// ListClassTypes godoc
// @Summary      List class types
// @Tags         classes
// @Produce      json
// @Security     BearerAuth
// @Param        active_only  query     bool  false  "Only return active class types"
// @Success      200  {array}   ClassTypeResponse
// @Router       /api/v1/class-types [get]
func (h *Handler) ListClassTypes(w http.ResponseWriter, r *http.Request) {
	activeOnly := r.URL.Query().Get("active_only") == "true"
	res, err := h.svc.ListClassTypes(r.Context(), activeOnly)
	if err != nil {
		writeErr(w, err, "list class types")
		return
	}
	response.OK(w, res)
}

// ─── Class schedules ──────────────────────────────────────────────────────────

// CreateSchedule godoc
// @Summary      Create a recurring class schedule
// @Description  Creates a recurrence rule and immediately materializes the first rolling window of sessions.
// @Tags         classes
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      CreateScheduleRequest  true  "Schedule details"
// @Success      201   {object}  ScheduleResponse
// @Failure      404   {object}  response.Envelope  "Class type not found"
// @Failure      422   {object}  response.Envelope
// @Router       /api/v1/class-schedules [post]
func (h *Handler) CreateSchedule(w http.ResponseWriter, r *http.Request) {
	var req CreateScheduleRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.CreateSchedule(r.Context(), req)
	if err != nil {
		writeErr(w, err, "create schedule")
		return
	}
	response.Created(w, res)
}

// ListSchedules godoc
// @Summary      List class schedules
// @Tags         classes
// @Produce      json
// @Security     BearerAuth
// @Param        active_only  query     bool  false  "Only return active schedules"
// @Success      200  {array}   ScheduleResponse
// @Router       /api/v1/class-schedules [get]
func (h *Handler) ListSchedules(w http.ResponseWriter, r *http.Request) {
	activeOnly := r.URL.Query().Get("active_only") == "true"
	res, err := h.svc.ListSchedules(r.Context(), activeOnly)
	if err != nil {
		writeErr(w, err, "list schedules")
		return
	}
	response.OK(w, res)
}

// GenerateUpcomingSessions godoc
// @Summary      Extend session materialization
// @Description  Rolls every active schedule's materialized sessions forward by the generation window.
// @Description  Idempotent — safe to call repeatedly (e.g. from a daily cron once one exists).
// @Tags         classes
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  response.Envelope
// @Router       /api/v1/class-schedules/generate [post]
func (h *Handler) GenerateUpcomingSessions(w http.ResponseWriter, r *http.Request) {
	n, err := h.svc.GenerateUpcomingSessions(r.Context())
	if err != nil {
		writeErr(w, err, "generate sessions")
		return
	}
	response.OK(w, map[string]any{"sessions_created": n})
}

// ─── Sessions ─────────────────────────────────────────────────────────────────

// CreateAdHocSession godoc
// @Summary      Create a one-off session
// @Description  Creates a single session not tied to any recurring schedule.
// @Tags         classes
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      CreateAdHocSessionRequest  true  "Session details"
// @Success      201   {object}  SessionResponse
// @Failure      404   {object}  response.Envelope  "Class type not found"
// @Router       /api/v1/class-sessions [post]
func (h *Handler) CreateAdHocSession(w http.ResponseWriter, r *http.Request) {
	var req CreateAdHocSessionRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.CreateAdHocSession(r.Context(), req)
	if err != nil {
		writeErr(w, err, "create session")
		return
	}
	response.Created(w, res)
}

// ListSessions godoc
// @Summary      List class sessions in a date range
// @Description  Returns sessions with live booked/waitlist counts — the booking screen's main read.
// @Tags         classes
// @Produce      json
// @Security     BearerAuth
// @Param        from  query     string  false  "YYYY-MM-DD, defaults to today"
// @Param        to    query     string  false  "YYYY-MM-DD, defaults to 7 days from today"
// @Success      200  {array}   SessionResponse
// @Router       /api/v1/class-sessions [get]
func (h *Handler) ListSessions(w http.ResponseWriter, r *http.Request) {
	from, err := parseDateOrToday(r.URL.Query().Get("from"))
	if err != nil {
		response.BadRequest(w, err.Error())
		return
	}
	to := from.AddDate(0, 0, 7)
	if raw := r.URL.Query().Get("to"); raw != "" {
		to, err = parseDateRequired(raw, "to")
		if err != nil {
			response.BadRequest(w, err.Error())
			return
		}
	}
	res, err := h.svc.ListSessions(r.Context(), from, to)
	if err != nil {
		writeErr(w, err, "list sessions")
		return
	}
	response.OK(w, res)
}

// GetSession godoc
// @Summary      Get a session
// @Tags         classes
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Session ID"
// @Success      200  {object}  SessionResponse
// @Failure      404  {object}  response.Envelope
// @Router       /api/v1/class-sessions/{id} [get]
func (h *Handler) GetSession(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	res, err := h.svc.Session(r.Context(), id)
	if err != nil {
		writeErr(w, err, "get session")
		return
	}
	response.OK(w, res)
}

// UpdateSession godoc
// @Summary      Edit one session
// @Description  Substitute trainer or one-off capacity change. Does not touch the recurring schedule.
// @Tags         classes
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                    true  "Session ID"
// @Param        body  body      UpdateSessionRequest   true  "Fields to change"
// @Success      200   {object}  SessionResponse
// @Failure      404   {object}  response.Envelope
// @Router       /api/v1/class-sessions/{id} [put]
func (h *Handler) UpdateSession(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	var req UpdateSessionRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.UpdateSession(r.Context(), id, req)
	if err != nil {
		writeErr(w, err, "update session")
		return
	}
	response.OK(w, res)
}

// CancelSession godoc
// @Summary      Cancel a session
// @Description  Cancels the session and every active booking on it.
// @Tags         classes
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Session ID"
// @Success      200  {object}  SessionResponse
// @Failure      404  {object}  response.Envelope
// @Failure      409  {object}  response.Envelope  "Already cancelled or completed"
// @Router       /api/v1/class-sessions/{id}/cancel [post]
func (h *Handler) CancelSession(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	res, err := h.svc.CancelSession(r.Context(), id)
	if err != nil {
		writeErr(w, err, "cancel session")
		return
	}
	response.OK(w, res)
}

// CompleteSession godoc
// @Summary      Mark a session as having run
// @Tags         classes
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Session ID"
// @Success      200  {object}  SessionResponse
// @Failure      404  {object}  response.Envelope
// @Router       /api/v1/class-sessions/{id}/complete [post]
func (h *Handler) CompleteSession(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	res, err := h.svc.CompleteSession(r.Context(), id)
	if err != nil {
		writeErr(w, err, "complete session")
		return
	}
	response.OK(w, res)
}

// ─── Bookings ─────────────────────────────────────────────────────────────────

// Book godoc
// @Summary      Book a member into a session
// @Description  Books the member, or places them on the waitlist if the session is full.
// @Tags         bookings
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                    true  "Session ID"
// @Param        body  body      CreateBookingRequest   true  "Member to book"
// @Success      201   {object}  BookingResult
// @Failure      404   {object}  response.Envelope
// @Failure      409   {object}  response.Envelope  "Frozen/terminated member, already booked, or session not bookable"
// @Router       /api/v1/class-sessions/{id}/bookings [post]
func (h *Handler) Book(w http.ResponseWriter, r *http.Request) {
	sessionID, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	var req CreateBookingRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.Book(r.Context(), sessionID, req)
	if err != nil {
		writeErr(w, err, "book")
		return
	}
	response.Created(w, res)
}

// SessionBookings godoc
// @Summary      A session's roster
// @Description  Every booking on a session — booked, waitlisted (in order), and past attendance/cancellations.
// @Tags         bookings
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Session ID"
// @Success      200  {array}   BookingResponse
// @Failure      404  {object}  response.Envelope
// @Router       /api/v1/class-sessions/{id}/bookings [get]
func (h *Handler) SessionBookings(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	res, err := h.svc.ListSessionBookings(r.Context(), id)
	if err != nil {
		writeErr(w, err, "session bookings")
		return
	}
	response.OK(w, res)
}

// CancelBooking godoc
// @Summary      Cancel a booking
// @Description  Cancels the booking. If it held a session slot, the oldest waitlisted member is promoted.
// @Tags         bookings
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                    true  "Booking ID"
// @Param        body  body      CancelBookingRequest   false "Optional reason"
// @Success      200   {object}  BookingResult
// @Failure      404   {object}  response.Envelope
// @Failure      409   {object}  response.Envelope  "Already cancelled"
// @Router       /api/v1/bookings/{id}/cancel [post]
func (h *Handler) CancelBooking(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	var req CancelBookingRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.Cancel(r.Context(), id, req)
	if err != nil {
		writeErr(w, err, "cancel booking")
		return
	}
	response.OK(w, res)
}

// MarkAttendance godoc
// @Summary      Mark a booking attended or no-show
// @Description  Only valid after the session's start time.
// @Tags         bookings
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                     true  "Booking ID"
// @Param        body  body      MarkAttendanceRequest   true  "attended: true/false"
// @Success      200   {object}  BookingResult
// @Failure      404   {object}  response.Envelope
// @Failure      422   {object}  response.Envelope  "Session hasn't started yet, or booking isn't in booked state"
// @Router       /api/v1/bookings/{id}/attendance [post]
func (h *Handler) MarkAttendance(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	var req MarkAttendanceRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.MarkAttendance(r.Context(), id, req)
	if err != nil {
		writeErr(w, err, "mark attendance")
		return
	}
	response.OK(w, res)
}

// MemberBookings godoc
// @Summary      A member's booking history
// @Tags         bookings
// @Produce      json
// @Security     BearerAuth
// @Param        member_id  path      int  true  "Member ID"
// @Success      200  {array}   BookingResponse
// @Router       /api/v1/members/{member_id}/bookings [get]
func (h *Handler) MemberBookings(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "member_id")
	if !ok {
		return
	}
	res, err := h.svc.ListMemberBookings(r.Context(), id)
	if err != nil {
		writeErr(w, err, "list member bookings")
		return
	}
	response.OK(w, res)
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

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

func writeErr(w http.ResponseWriter, err error, op string) {
	switch {
	case errors.Is(err, ErrClassTypeNotFound),
		errors.Is(err, ErrScheduleNotFound),
		errors.Is(err, ErrSessionNotFound),
		errors.Is(err, ErrMemberNotFound),
		errors.Is(err, ErrBookingNotFound):
		response.NotFound(w, err.Error())

	case errors.Is(err, ErrClassTypeInactive),
		errors.Is(err, ErrSessionAlreadyCancelled),
		errors.Is(err, ErrSessionAlreadyCompleted),
		errors.Is(err, ErrCannotCancelCompleted),
		errors.Is(err, ErrSessionAlreadyStarted),
		errors.Is(err, ErrSessionNotBookable),
		errors.Is(err, ErrAlreadyBooked),
		errors.Is(err, ErrMemberFrozen),
		errors.Is(err, ErrMemberTerminated),
		errors.Is(err, ErrBookingAlreadyCancelled):
		response.Conflict(w, err.Error())

	case errors.Is(err, ErrInvalidDayOfWeek),
		errors.Is(err, ErrInvalidDateRange),
		errors.Is(err, ErrCannotMarkBeforeSession):
		response.UnprocessableEntity(w, err.Error())

	default:
		if isValidationErr(err) {
			response.UnprocessableEntity(w, err.Error())
			return
		}
		log.Printf("classes %s: %v", op, err)
		response.InternalServerError(w)
	}
}

func isValidationErr(err error) bool {
	msg := err.Error()
	for _, marker := range []string{
		"invalid date", "is required", "expected YYYY-MM-DD", "expected HH:MM",
		"must be greater than 0", "member_id is required",
	} {
		if strings.Contains(msg, marker) {
			return true
		}
	}
	return false
}
