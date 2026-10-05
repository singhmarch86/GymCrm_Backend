package dashboard

import (
	"net/http"

	"gymcrm/internal/shared/response"
)

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{
		service: service,
	}
}

func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/dashboard", h.GetDashboard)
}

func (h *Handler) GetDashboard(w http.ResponseWriter, r *http.Request) {
	data, err := h.service.GetDashboard(r.Context())
	if err != nil {
		response.InternalServerError(w)
		return
	}

	response.OK(w, data)
}
