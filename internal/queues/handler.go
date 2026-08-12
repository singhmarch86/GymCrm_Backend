package queues

import (
	"log"
	"net/http"

	"gymcrm/internal/shared/response"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/queues/stock", h.Stock)
}

// Stock godoc
// @Summary      Products at or below their reorder level
// @Description  Out of stock first, then running low. Both groups are always returned, empty or not.
// @Tags         queues
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  StockQueue
// @Router       /api/v1/queues/stock [get]
func (h *Handler) Stock(w http.ResponseWriter, r *http.Request) {
	queue, err := h.svc.Stock(r.Context())
	if err != nil {
		log.Printf("queues: stock: %v", err)
		response.InternalServerError(w)
		return
	}
	response.OK(w, queue)
}
