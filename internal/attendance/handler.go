package attendance

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"

	"gymcrm/internal/shared/pagination"
	"gymcrm/internal/shared/response"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// RegisterRoutes mounts all attendance endpoints.
// All routes require JWT — caller wraps with JWTMiddleware.
func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/attendance/checkin",           h.CheckIn)
	mux.HandleFunc("GET /api/v1/attendance/today",              h.Today)
	mux.HandleFunc("GET /api/v1/attendance/recent",             h.Recent)
	mux.HandleFunc("GET /api/v1/attendance/date/{date}",        h.ByDate)
	mux.HandleFunc("GET /api/v1/attendance/member/{member_id}", h.ByMember)
}

// CheckIn godoc
// @Summary      Check in a member
// @Description  Records a member attendance for today. Server sets the timestamp.
//               Returns 409 if the member has already checked in today.
//               gym_id comes from JWT — never from payload.
// @Tags         attendance
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      CheckInRequest  true  "Member ID to check in"
// @Success      201   {object}  AttendanceResponse
// @Failure      404   {object}  response.Envelope  "Member not found"
// @Failure      409   {object}  response.Envelope  "Already checked in today"
// @Failure      422   {object}  response.Envelope  "Validation error"
// @Failure      401   {object}  response.Envelope
// @Router       /api/v1/attendance/checkin [post]
func (h *Handler) CheckIn(w http.ResponseWriter, r *http.Request) {
	var req CheckInRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "invalid request body")
		return
	}
	if err := ValidateCheckInRequest(&req); err != nil {
		response.UnprocessableEntity(w, err.Error())
		return
	}
	result, err := h.svc.CheckIn(r.Context(), req)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.Created(w, result)
}

// Today godoc
// @Summary      Get today's attendance
// @Description  Returns all check-ins for today in the authenticated gym.
//               Sorted by check-in time descending (most recent first).
// @Tags         attendance
// @Produce      json
// @Security     BearerAuth
// @Param        page      query  int  false  "Page number (default: 1)"
// @Param        per_page  query  int  false  "Items per page (default: 20, max: 100)"
// @Success      200  {object}  AttendanceListResponse
// @Failure      401  {object}  response.Envelope
// @Router       /api/v1/attendance/today [get]
func (h *Handler) Today(w http.ResponseWriter, r *http.Request) {
	p := pagination.FromRequest(r)
	records, total, err := h.svc.GetToday(r.Context(), p)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.JSONWithMeta(w, http.StatusOK,
		AttendanceListResponse{Attendance: records},
		pagination.BuildMeta(p, total),
	)
}

// ByDate godoc
// @Summary      Get attendance for a specific date
// @Description  Returns all check-ins for the given date (YYYY-MM-DD) in the authenticated gym.
// @Tags         attendance
// @Produce      json
// @Security     BearerAuth
// @Param        date      path   string  true   "Date in YYYY-MM-DD format"
// @Param        page      query  int     false  "Page number"
// @Param        per_page  query  int     false  "Items per page"
// @Success      200  {object}  AttendanceListResponse
// @Failure      400  {object}  response.Envelope  "Invalid date format"
// @Failure      401  {object}  response.Envelope
// @Router       /api/v1/attendance/date/{date} [get]
func (h *Handler) ByDate(w http.ResponseWriter, r *http.Request) {
	dateStr := r.PathValue("date")
	if dateStr == "" {
		response.BadRequest(w, "date is required")
		return
	}
	p := pagination.FromRequest(r)
	records, total, err := h.svc.GetByDate(r.Context(), dateStr, p)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.JSONWithMeta(w, http.StatusOK,
		AttendanceListResponse{Attendance: records},
		pagination.BuildMeta(p, total),
	)
}

// ByMember godoc
// @Summary      Get attendance history for a member
// @Description  Returns all check-ins for a specific member, sorted by date descending.
//               Returns 404 if the member doesn't belong to the authenticated gym.
// @Tags         attendance
// @Produce      json
// @Security     BearerAuth
// @Param        member_id  path   int  true   "Member ID"
// @Param        page       query  int  false  "Page number"
// @Param        per_page   query  int  false  "Items per page"
// @Success      200  {object}  AttendanceListResponse
// @Failure      404  {object}  response.Envelope  "Member not found"
// @Failure      401  {object}  response.Envelope
// @Router       /api/v1/attendance/member/{member_id} [get]
func (h *Handler) ByMember(w http.ResponseWriter, r *http.Request) {
	memberID, err := pathID(r, "member_id")
	if err != nil {
		response.BadRequest(w, "invalid member id")
		return
	}
	p := pagination.FromRequest(r)
	records, total, err := h.svc.GetMemberAttendance(r.Context(), memberID, p)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.JSONWithMeta(w, http.StatusOK,
		AttendanceListResponse{Attendance: records},
		pagination.BuildMeta(p, total),
	)
}

// Recent godoc
// @Summary      Get recent check-ins
// @Description  Returns the last N check-ins across all members in the gym.
//               Sorted by check-in time descending. Use for live activity feed.
//               Default limit: 20. Max: 100.
// @Tags         attendance
// @Produce      json
// @Security     BearerAuth
// @Param        limit  query  int  false  "Number of records (default: 20, max: 100)"
// @Success      200    {object}  AttendanceListResponse
// @Failure      401    {object}  response.Envelope
// @Router       /api/v1/attendance/recent [get]
func (h *Handler) Recent(w http.ResponseWriter, r *http.Request) {
	limit := 20
	if raw := r.URL.Query().Get("limit"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 {
			limit = n
		}
	}
	records, err := h.svc.GetRecent(r.Context(), limit)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, AttendanceListResponse{Attendance: records})
}

// ─── Error mapping ────────────────────────────────────────────────────────────

func (h *Handler) handleError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrMemberNotFound):
		response.NotFound(w, "member not found")
	case errors.Is(err, ErrAlreadyCheckedIn):
		response.Conflict(w, "member already checked in today")
	case errors.Is(err, ErrAttendanceNotFound):
		response.NotFound(w, "attendance record not found")
	case errors.Is(err, ErrInvalidDate):
		response.BadRequest(w, "date must be in YYYY-MM-DD format")
	default:
		log.Printf("ERROR attendance handler: %v", err)
		response.InternalServerError(w)
	}
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

func pathID(r *http.Request, key string) (int64, error) {
	return strconv.ParseInt(r.PathValue(key), 10, 64)
}
