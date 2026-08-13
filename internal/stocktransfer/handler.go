package stocktransfer

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"

	"gymcrm/internal/shared/response"
)

type Handler struct{ svc *Service }

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/stock/chain", h.Chain)
	mux.HandleFunc("POST /api/v1/stock/transfer", h.Send)
	mux.HandleFunc("GET /api/v1/stock/transfers", h.History)
}

// Chain godoc
// @Summary      Stock across every branch you hold
// @Description  One row per item, one column per branch, with what each branch holds against its own reorder level. Read-only. Flags items short at one branch while another has a surplus, and separately those short everywhere — which no transfer can fix.
// @Tags         stock
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  ChainStock
// @Router       /api/v1/stock/chain [get]
func (h *Handler) Chain(w http.ResponseWriter, r *http.Request) {
	out, err := h.svc.Chain(r.Context())
	if err != nil {
		log.Printf("chain stock: %v", err)
		response.InternalServerError(w)
		return
	}
	response.OK(w, out)
}

type sendRequest struct {
	ProductID int64  `json:"product_id"`
	ToGymID   int64  `json:"to_gym_id"`
	Quantity  int    `json:"quantity"`
	Reason    string `json:"reason"`
}

// Send godoc
// @Summary      Move stock from your branch to another
// @Description  Writes both stock movements and a transfer record in one transaction. Creates the product at the destination if it does not carry the item yet, copying price and cost from the sender.
// @Tags         stock
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        request  body  sendRequest  true  "What to send, where"
// @Success      201  {object}  Transfer
// @Router       /api/v1/stock/transfer [post]
func (h *Handler) Send(w http.ResponseWriter, r *http.Request) {
	var req sendRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "could not read the request")
		return
	}
	if req.ProductID == 0 || req.ToGymID == 0 {
		response.BadRequest(w, "product_id and to_gym_id are both required")
		return
	}

	t, err := h.svc.Send(r.Context(), req.ProductID, req.ToGymID,
		req.Quantity, strings.TrimSpace(req.Reason))
	if err != nil {
		writeErr(w, err)
		return
	}
	response.Created(w, t)
}

// History godoc
// @Summary      Transfers into and out of your branch
// @Tags         stock
// @Produce      json
// @Security     BearerAuth
// @Param        limit  query  int  false  "Rows to return; default 50, max 200"
// @Success      200  {array}  TransferRow
// @Router       /api/v1/stock/transfers [get]
func (h *Handler) History(w http.ResponseWriter, r *http.Request) {
	limit := 0
	if raw := strings.TrimSpace(r.URL.Query().Get("limit")); raw != "" {
		if n, convErr := strconv.Atoi(raw); convErr == nil {
			limit = n
		}
	}

	rows, err := h.svc.History(r.Context(), limit)
	if err != nil {
		log.Printf("transfer history: %v", err)
		response.InternalServerError(w)
		return
	}
	response.OK(w, rows)
}

// writeErr maps the refusals to statuses. Each one is a sentence a person at
// the front desk can act on, because they are the ones who will see it.
func writeErr(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrBadQuantity):
		response.BadRequest(w, "send between 1 and 9999 units")
	case errors.Is(err, ErrSameBranch):
		response.BadRequest(w, "that is the branch you are already in")
	case errors.Is(err, ErrNoAccess):
		response.Forbidden(w, "you do not have access to that branch")
	case errors.Is(err, ErrDifferentOrg):
		response.Forbidden(w, "that branch is not part of your organisation")
	case errors.Is(err, ErrProductNotFound):
		response.NotFound(w, "that product is not stocked at your branch")
	case errors.Is(err, ErrNotEnoughStock):
		// 422 rather than 400: the request was well formed and the shelf
		// simply does not hold that much.
		response.UnprocessableEntity(w, "your branch does not have that many to send")
	default:
		log.Printf("stock transfer: %v", err)
		response.InternalServerError(w)
	}
}
