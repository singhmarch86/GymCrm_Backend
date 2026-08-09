package counter

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"

	"gymcrm/internal/database"
	"gymcrm/internal/shared/response"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

// ActedRequest is the optional payload when marking a prompt acted on.
type ActedRequest struct {
	ActionNote string `json:"action_note,omitempty"`
}

// EffectivenessResponse wraps the per-kind scoreboard.
type EffectivenessResponse struct {
	Kinds []EffectivenessRow `json:"kinds"`
	Days  int                `json:"days"`
}

// Show godoc
// @Summary      The one thing worth saying to this member right now
// @Description  Records that the prompt was shown, which drives the 7-day cooldown. Use the peek endpoint to look without recording.
// @Tags         counter
// @Produce      json
// @Security     BearerAuth
// @Param        member_id  path  int  true  "Member ID"
// @Success      200  {object}  Result
// @Router       /api/v1/counter/checkin/{member_id} [post]
func (h *Handler) Show(w http.ResponseWriter, r *http.Request) {
	id, ok := memberID(w, r)
	if !ok {
		return
	}
	tc := database.MustGetTenant(r.Context())
	result, err := h.svc.ForCheckIn(r.Context(), id, tc.UserID())
	if err != nil {
		h.fail(w, err)
		return
	}
	response.OK(w, result)
}

// Peek godoc
// @Summary      The same prompt, without recording that it was shown
// @Description  For when staff pull a member up on screen. Does not burn the cooldown.
// @Tags         counter
// @Produce      json
// @Security     BearerAuth
// @Param        member_id  path  int  true  "Member ID"
// @Success      200  {object}  Result
// @Router       /api/v1/counter/prompt/{member_id} [get]
func (h *Handler) Peek(w http.ResponseWriter, r *http.Request) {
	id, ok := memberID(w, r)
	if !ok {
		return
	}
	result, err := h.svc.Peek(r.Context(), id)
	if err != nil {
		h.fail(w, err)
		return
	}
	response.OK(w, result)
}

// MarkActed godoc
// @Summary      Record that the staff member acted on a prompt
// @Tags         counter
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id  path  int  true  "Prompt log ID"
// @Success      204
// @Failure      404  {object}  response.Envelope
// @Router       /api/v1/counter/prompts/{id}/acted [patch]
func (h *Handler) MarkActed(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || id <= 0 {
		response.BadRequest(w, "invalid prompt id")
		return
	}
	var req ActedRequest
	// An empty body is fine — the note is optional (FR-11 §5).
	_ = json.NewDecoder(r.Body).Decode(&req)

	ok, err := h.svc.MarkActed(r.Context(), id, req.ActionNote)
	if err != nil {
		h.fail(w, err)
		return
	}
	if !ok {
		response.NotFound(w, "prompt not found")
		return
	}
	response.NoContent(w)
}

// Effectiveness godoc
// @Summary      Which prompts staff actually act on
// @Description  A kind nobody ever acts on is noise and should be switched off.
// @Tags         counter
// @Produce      json
// @Security     BearerAuth
// @Param        days  query  int  false  "Window in days (default 30)"
// @Success      200  {object}  EffectivenessResponse
// @Router       /api/v1/counter/effectiveness [get]
func (h *Handler) Effectiveness(w http.ResponseWriter, r *http.Request) {
	days := 30
	if raw := r.URL.Query().Get("days"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil {
			days = n
		}
	}
	rows, err := h.svc.Effectiveness(r.Context(), days)
	if err != nil {
		h.fail(w, err)
		return
	}
	response.OK(w, EffectivenessResponse{Kinds: rows, Days: days})
}

func memberID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, err := strconv.ParseInt(r.PathValue("member_id"), 10, 64)
	if err != nil || id <= 0 {
		response.BadRequest(w, "invalid member id")
		return 0, false
	}
	return id, true
}

func (h *Handler) fail(w http.ResponseWriter, err error) {
	log.Printf("counter: %v", err)
	response.InternalServerError(w)
}
