package trainers

import (
	"encoding/json"
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

func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/trainers", h.Create)
	mux.HandleFunc("GET /api/v1/trainers", h.List)
	mux.HandleFunc("PUT /api/v1/trainers/{id}", h.Update)
}

// Create godoc
// @Summary      Add a trainer
// @Tags         trainers
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      CreateTrainerRequest  true  "Trainer details"
// @Success      201   {object}  TrainerResponse
// @Failure      422   {object}  response.Envelope
// @Router       /api/v1/trainers [post]
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	var req CreateTrainerRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.Create(r.Context(), req)
	if err != nil {
		writeErr(w, err, "create trainer")
		return
	}
	response.Created(w, res)
}

// List godoc
// @Summary      List trainers
// @Tags         trainers
// @Produce      json
// @Security     BearerAuth
// @Param        active_only  query     bool  false  "Only return active trainers"
// @Success      200  {array}   TrainerResponse
// @Router       /api/v1/trainers [get]
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	activeOnly := r.URL.Query().Get("active_only") == "true"
	res, err := h.svc.List(r.Context(), activeOnly)
	if err != nil {
		writeErr(w, err, "list trainers")
		return
	}
	response.OK(w, res)
}

// Update godoc
// @Summary      Edit a trainer
// @Tags         trainers
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                    true  "Trainer ID"
// @Param        body  body      UpdateTrainerRequest   true  "Fields to change"
// @Success      200   {object}  TrainerResponse
// @Failure      404   {object}  response.Envelope
// @Router       /api/v1/trainers/{id} [put]
func (h *Handler) Update(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	var req UpdateTrainerRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.Update(r.Context(), id, req)
	if err != nil {
		writeErr(w, err, "update trainer")
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

func writeErr(w http.ResponseWriter, err error, op string) {
	switch {
	case errors.Is(err, ErrNotFound):
		response.NotFound(w, err.Error())
	case errors.Is(err, ErrNameRequired), errors.Is(err, ErrPhoneRequired), errors.Is(err, ErrInvalidCommission):
		response.UnprocessableEntity(w, err.Error())
	default:
		log.Printf("trainers %s: %v", op, err)
		response.InternalServerError(w)
	}
}
