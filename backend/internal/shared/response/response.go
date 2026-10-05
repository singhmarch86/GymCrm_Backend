package response

import (
	"encoding/json"
	"net/http"
)

// Envelope is the standard API response wrapper for every endpoint.
// Frontend always receives the same shape — success or error.
//
//	{ "success": true,  "data": {...},  "meta": {...} }
//	{ "success": false, "error": {...} }
type Envelope struct {
	Success bool        `json:"success"`
	Data    interface{} `json:"data,omitempty"`
	Error   *APIError   `json:"error,omitempty"`
	Meta    *Meta       `json:"meta,omitempty"`
}

// APIError is the structured error payload.
type APIError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// Meta carries pagination metadata when returning lists.
type Meta struct {
	Page       int   `json:"page"`
	PerPage    int   `json:"per_page"`
	Total      int64 `json:"total"`
	TotalPages int   `json:"total_pages"`
}

// ─── Success helpers ──────────────────────────────────────────────────────────

func JSON(w http.ResponseWriter, status int, data interface{}) {
	write(w, status, Envelope{Success: true, Data: data})
}

func JSONWithMeta(w http.ResponseWriter, status int, data interface{}, meta *Meta) {
	write(w, status, Envelope{Success: true, Data: data, Meta: meta})
}

func Created(w http.ResponseWriter, data interface{}) {
	JSON(w, http.StatusCreated, data)
}

func OK(w http.ResponseWriter, data interface{}) {
	JSON(w, http.StatusOK, data)
}

func NoContent(w http.ResponseWriter) {
	w.WriteHeader(http.StatusNoContent)
}

// ─── Error helpers ────────────────────────────────────────────────────────────

func BadRequest(w http.ResponseWriter, message string) {
	writeError(w, http.StatusBadRequest, "BAD_REQUEST", message)
}

func Unauthorized(w http.ResponseWriter, message string) {
	writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", message)
}

func Forbidden(w http.ResponseWriter, message string) {
	writeError(w, http.StatusForbidden, "FORBIDDEN", message)
}

func NotFound(w http.ResponseWriter, message string) {
	writeError(w, http.StatusNotFound, "NOT_FOUND", message)
}

func Conflict(w http.ResponseWriter, message string) {
	writeError(w, http.StatusConflict, "CONFLICT", message)
}

func UnprocessableEntity(w http.ResponseWriter, message string) {
	writeError(w, http.StatusUnprocessableEntity, "VALIDATION_ERROR", message)
}

func InternalServerError(w http.ResponseWriter) {
	writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "something went wrong")
}

// ─── Private ──────────────────────────────────────────────────────────────────

func writeError(w http.ResponseWriter, status int, code, message string) {
	write(w, status, Envelope{
		Success: false,
		Error:   &APIError{Code: code, Message: message},
	})
}

func write(w http.ResponseWriter, status int, body Envelope) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}
