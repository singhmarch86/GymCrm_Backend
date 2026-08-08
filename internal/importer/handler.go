package importer

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

func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/imports", h.Validate)
	mux.HandleFunc("GET /api/v1/imports", h.List)
	mux.HandleFunc("GET /api/v1/imports/{id}", h.Get)
	mux.HandleFunc("POST /api/v1/imports/{id}/commit", h.Commit)
	mux.HandleFunc("DELETE /api/v1/imports/{id}", h.Discard)
	mux.HandleFunc("GET /api/v1/imports/template", h.Template)
}

// Validate godoc
// @Summary      Validate a CSV upload
// @Description  Parses and checks every row. Writes nothing to real data — commit does that.
// @Tags         import
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      ValidateRequest  true  "CSV upload"
// @Success      201   {object}  BatchResponse
// @Failure      422   {object}  response.Envelope  "Unparseable file or unknown entity"
// @Router       /api/v1/imports [post]
func (h *Handler) Validate(w http.ResponseWriter, r *http.Request) {
	var req ValidateRequest
	if !decode(w, r, &req) {
		return
	}
	if strings.TrimSpace(req.Content) == "" {
		response.UnprocessableEntity(w, "no file content was provided")
		return
	}
	res, err := h.svc.Validate(r.Context(), req.EntityType, req.Filename, req.Content)
	if err != nil {
		writeErr(w, err, "validate import")
		return
	}
	response.Created(w, res)
}

// List godoc
// @Summary      Import history
// @Tags         import
// @Produce      json
// @Security     BearerAuth
// @Success      200  {array}  BatchSummaryResponse
// @Router       /api/v1/imports [get]
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	res, err := h.svc.ListBatches(r.Context())
	if err != nil {
		writeErr(w, err, "list imports")
		return
	}
	response.OK(w, res)
}

// Get godoc
// @Summary      One import with its rows
// @Tags         import
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Import ID"
// @Success      200  {object}  BatchResponse
// @Router       /api/v1/imports/{id} [get]
func (h *Handler) Get(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	res, err := h.svc.GetBatch(r.Context(), id)
	if err != nil {
		writeErr(w, err, "get import")
		return
	}
	response.OK(w, res)
}

// Commit godoc
// @Summary      Commit a validated import
// @Description  Creates the records. Each row commits independently, so one failure cannot roll back the rest.
// @Tags         import
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int            true   "Import ID"
// @Param        body  body      CommitRequest  false  "Duplicate policy"
// @Success      200   {object}  BatchResponse
// @Failure      409   {object}  response.Envelope  "Already committed or discarded"
// @Router       /api/v1/imports/{id}/commit [post]
func (h *Handler) Commit(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var req CommitRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.Commit(r.Context(), id, req.DuplicatePolicy)
	if err != nil {
		writeErr(w, err, "commit import")
		return
	}
	response.OK(w, res)
}

// Discard godoc
// @Summary      Throw away an uncommitted import
// @Tags         import
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Import ID"
// @Success      200  {object}  response.Envelope
// @Router       /api/v1/imports/{id} [delete]
func (h *Handler) Discard(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	if err := h.svc.Discard(r.Context(), id); err != nil {
		writeErr(w, err, "discard import")
		return
	}
	response.OK(w, map[string]string{"status": "discarded"})
}

// Template godoc
// @Summary      Download a starter CSV
// @Tags         import
// @Produce      plain
// @Security     BearerAuth
// @Param        entity  query  string  true  "members | plans | payments"
// @Success      200     {string}  string  "CSV"
// @Router       /api/v1/imports/template [get]
func (h *Handler) Template(w http.ResponseWriter, r *http.Request) {
	entity := r.URL.Query().Get("entity")
	if entity == "" {
		entity = EntityMembers
	}
	w.Header().Set("Content-Type", "text/csv; charset=utf-8")
	w.Header().Set("Content-Disposition", "attachment; filename=\""+entity+"_template.csv\"")
	_, _ = w.Write([]byte(TemplateFor(entity)))
}

// ─── helpers ──────────────────────────────────────────────────────────────────

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

func writeErr(w http.ResponseWriter, err error, op string) {
	switch {
	case errors.Is(err, ErrBatchNotFound):
		response.NotFound(w, err.Error())
	case errors.Is(err, ErrBatchNotValidated):
		response.Conflict(w, err.Error())
	case errors.Is(err, ErrUnknownEntity), errors.Is(err, ErrEmptyFile):
		response.UnprocessableEntity(w, err.Error())
	default:
		// Parse failures are the user's file being wrong, not our bug — they
		// must come back as something they can act on.
		msg := err.Error()
		if strings.Contains(msg, "CSV") || strings.Contains(msg, "header") || strings.Contains(msg, "empty") {
			response.UnprocessableEntity(w, msg)
			return
		}
		log.Printf("import %s: %v", op, err)
		response.InternalServerError(w)
	}
}
