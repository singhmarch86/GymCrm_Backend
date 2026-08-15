package ptfeedback

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"

	"gymcrm/internal/shared/response"
)

type Handler struct{ svc *Service }

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/pt/feedback", h.Create)
	mux.HandleFunc("GET /api/v1/members/{id}/feedback", h.ByMember)
	mux.HandleFunc("GET /api/v1/trainers/{id}/feedback", h.ByTrainer)
}

// Create godoc
// @Summary      Log PT feedback
// @Description  One shared log for both "what the member said" and "what the trainer observed" — author_role distinguishes whose words they are. Both are staff-transcribed.
// @Tags         pt-feedback
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      CreateRequest  true  "Feedback details"
// @Success      201   {object}  Row
// @Router       /api/v1/pt/feedback [post]
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	var req CreateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "could not read the request")
		return
	}
	out, err := h.svc.Create(r.Context(), req)
	if err != nil {
		writeErr(w, err)
		return
	}
	response.Created(w, out)
}

// ByMember godoc
// @Summary      A member's feedback history
// @Tags         pt-feedback
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Member ID"
// @Success      200  {array}   Row
// @Router       /api/v1/members/{id}/feedback [get]
func (h *Handler) ByMember(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		response.BadRequest(w, "invalid member id")
		return
	}
	rows, err := h.svc.ByMember(r.Context(), id)
	if err != nil {
		log.Printf("member feedback: %v", err)
		response.InternalServerError(w)
		return
	}
	response.OK(w, rows)
}

// ByTrainer godoc
// @Summary      Feedback a trainer has given
// @Tags         pt-feedback
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Trainer ID"
// @Success      200  {array}   Row
// @Router       /api/v1/trainers/{id}/feedback [get]
func (h *Handler) ByTrainer(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		response.BadRequest(w, "invalid trainer id")
		return
	}
	rows, err := h.svc.ByTrainer(r.Context(), id)
	if err != nil {
		log.Printf("trainer feedback: %v", err)
		response.InternalServerError(w)
		return
	}
	response.OK(w, rows)
}

func writeErr(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrBadAuthorRole), errors.Is(err, ErrBlankNote):
		response.BadRequest(w, err.Error())
	case errors.Is(err, ErrMemberNotHere), errors.Is(err, ErrTrainerNotHere):
		response.NotFound(w, err.Error())
	default:
		log.Printf("pt feedback: %v", err)
		response.InternalServerError(w)
	}
}
