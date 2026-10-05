package payouts

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

func decode(w http.ResponseWriter, r *http.Request, dst interface{}) bool {
	if err := json.NewDecoder(r.Body).Decode(dst); err != nil {
		response.BadRequest(w, "invalid JSON body")
		return false
	}
	return true
}

func fail(w http.ResponseWriter, err error, what string) {
	switch {
	case errors.Is(err, ErrTrainerNotFound):
		response.NotFound(w, "no such trainer")
	case errors.Is(err, ErrBadPeriod):
		response.BadRequest(w,
			"from and to must be YYYY-MM-DD, and to cannot be before from")
	case errors.Is(err, ErrSalaryNeedsMonth):
		response.BadRequest(w,
			"this trainer is on a salary, so the period must be one whole "+
				"calendar month — pro-rating a salary across part of a month "+
				"would invent a figure nobody agreed to")
	case errors.Is(err, ErrAlreadyExists):
		response.BadRequest(w,
			"a payout already covers that period for this trainer")
	case errors.Is(err, ErrNothingToPay):
		response.BadRequest(w, "that period earns nothing")
	case errors.Is(err, ErrOwnerOnly):
		response.Forbidden(w, "only an owner can record a payment")
	case errors.Is(err, ErrNotDraft):
		response.BadRequest(w, "that payout is not a draft any more")
	default:
		log.Printf("payouts: %s: %v", what, err)
		response.InternalServerError(w)
	}
}

// Preview godoc
// @Summary      What a trainer would be paid for a period
// @Description  Computes salary, commission on PT the gym has actually been paid for, and per-session earnings, without writing anything. Also reports PT sold but not yet collected, which is deliberately NOT part of the total.
// @Tags         payouts
// @Produce      json
// @Security     BearerAuth
// @Param        trainer_id  path   int     true  "Trainer ID"
// @Param        from        query  string  true  "YYYY-MM-DD"
// @Param        to          query  string  true  "YYYY-MM-DD"
// @Success      200  {object}  Preview
// @Router       /api/v1/trainers/{trainer_id}/payout-preview [get]
func (h *Handler) Preview(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("trainer_id"), 10, 64)
	if err != nil || id <= 0 {
		response.BadRequest(w, "invalid trainer id")
		return
	}
	q := r.URL.Query()

	out, err := h.svc.Preview(r.Context(), id,
		strings.TrimSpace(q.Get("from")), strings.TrimSpace(q.Get("to")))
	if err != nil {
		fail(w, err, "preview")
		return
	}
	response.OK(w, out)
}

type createRequest struct {
	TrainerID         int64  `json:"trainer_id"`
	From              string `json:"from"`
	To                string `json:"to"`
	AdjustmentInPaise int64  `json:"adjustment_in_paise"`
	AdjustmentReason  string `json:"adjustment_reason"`
	Notes             string `json:"notes"`
}

// Create godoc
// @Summary      Store a draft payout
// @Description  Same computation the preview showed. Always a draft — recording the money as paid is a separate, owner-only step.
// @Tags         payouts
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      createRequest  true  "Period and any adjustment"
// @Success      200   {object}  Payout
// @Router       /api/v1/payouts [post]
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	var req createRequest
	if !decode(w, r, &req) {
		return
	}
	if req.AdjustmentInPaise != 0 &&
		strings.TrimSpace(req.AdjustmentReason) == "" {
		response.BadRequest(w,
			"an adjustment needs a reason — an unexplained change to "+
				"somebody's pay is the row nobody can answer for later")
		return
	}

	out, err := h.svc.Create(r.Context(), req.TrainerID, req.From, req.To,
		req.AdjustmentInPaise, strings.TrimSpace(req.AdjustmentReason),
		strings.TrimSpace(req.Notes))
	if err != nil {
		fail(w, err, "create")
		return
	}
	response.OK(w, out)
}

type payRequest struct {
	PaymentMode     string `json:"payment_mode"`
	ReferenceNumber string `json:"reference_number"`
}

// MarkPaid godoc
// @Summary      Record that a payout was paid
// @Description  Owner only. Stamps who released the money and when.
// @Tags         payouts
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path  int         true  "Payout ID"
// @Param        body  body  payRequest  true  "How it was paid"
// @Success      204
// @Router       /api/v1/payouts/{id}/pay [post]
func (h *Handler) MarkPaid(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || id <= 0 {
		response.BadRequest(w, "invalid payout id")
		return
	}
	var req payRequest
	if !decode(w, r, &req) {
		return
	}

	if err := h.svc.MarkPaid(r.Context(), id,
		strings.TrimSpace(req.PaymentMode),
		strings.TrimSpace(req.ReferenceNumber)); err != nil {
		fail(w, err, "mark paid")
		return
	}
	response.NoContent(w)
}

// Cancel godoc
// @Summary      Abandon a draft payout
// @Tags         payouts
// @Produce      json
// @Security     BearerAuth
// @Param        id  path  int  true  "Payout ID"
// @Success      204
// @Router       /api/v1/payouts/{id}/cancel [post]
func (h *Handler) Cancel(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || id <= 0 {
		response.BadRequest(w, "invalid payout id")
		return
	}
	if err := h.svc.Cancel(r.Context(), id); err != nil {
		fail(w, err, "cancel")
		return
	}
	response.NoContent(w)
}

// List godoc
// @Summary      Payouts, newest period first
// @Tags         payouts
// @Produce      json
// @Security     BearerAuth
// @Param        status  query  string  false  "draft | paid | cancelled"
// @Success      200  {array}  Payout
// @Router       /api/v1/payouts [get]
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	out, err := h.svc.List(r.Context(),
		strings.TrimSpace(r.URL.Query().Get("status")))
	if err != nil {
		fail(w, err, "list")
		return
	}
	response.OK(w, out)
}

// Get godoc
// @Summary      One payout with the lines behind its total
// @Tags         payouts
// @Produce      json
// @Security     BearerAuth
// @Param        id  path  int  true  "Payout ID"
// @Success      200  {object}  Payout
// @Router       /api/v1/payouts/{id} [get]
func (h *Handler) Get(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || id <= 0 {
		response.BadRequest(w, "invalid payout id")
		return
	}
	out, err := h.svc.Get(r.Context(), id)
	if err != nil {
		response.NotFound(w, "no such payout")
		return
	}
	response.OK(w, out)
}
