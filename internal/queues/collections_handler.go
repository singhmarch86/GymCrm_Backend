package queues

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"gymcrm/internal/shared/response"
)

// Collections godoc
// @Summary      Money the gym is owed and has not collected
// @Description  Grouped worst-first: unchased, chased, promised, due later.
// @Tags         queues
// @Produce      json
// @Security     BearerAuth
// @Param        from  query  string  false  "YYYY-MM-DD, filters by due date; must be paired with to"
// @Param        to    query  string  false  "YYYY-MM-DD, filters by due date; must be paired with from"
// @Success      200  {object}  CollectionQueue
// @Router       /api/v1/queues/collections [get]
func (h *Handler) Collections(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	from := strings.TrimSpace(q.Get("from"))
	to := strings.TrimSpace(q.Get("to"))

	// Both or neither. A lone bound silently completed to today would answer a
	// question nobody asked, and on a debt list that means hiding money.
	if (from == "") != (to == "") {
		response.BadRequest(w, "from and to must both be given")
		return
	}
	if from != "" {
		f, errF := time.ParseInLocation("2006-01-02", from, IST)
		t, errT := time.ParseInLocation("2006-01-02", to, IST)
		if errF != nil || errT != nil {
			response.BadRequest(w, "from and to must be in YYYY-MM-DD format")
			return
		}
		if t.Before(f) {
			response.BadRequest(w, "to must not be before from")
			return
		}
	}

	queue, err := h.svc.Collections(r.Context(), from, to)
	if err != nil {
		log.Printf("queues: collections: %v", err)
		response.InternalServerError(w)
		return
	}
	response.OK(w, queue)
}

type contactRequest struct {
	Channel string `json:"channel"` // call | message | in_person
	Reached bool   `json:"reached"`
	Note    string `json:"note"`
}

// RecordContact godoc
// @Summary      Record an attempt to collect a due
// @Tags         queues
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path  int             true  "Payment ID"
// @Param        body  body  contactRequest  true  "Contact"
// @Success      204
// @Router       /api/v1/payments/{id}/contact [post]
func (h *Handler) RecordContact(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}

	var req contactRequest
	if !decode(w, r, &req) {
		return
	}

	switch req.Channel {
	case "call", "message", "in_person":
	default:
		response.BadRequest(w, "channel must be call, message or in_person")
		return
	}

	err := h.svc.RecordContact(r.Context(), id, req.Channel, req.Reached, req.Note)
	if err != nil {
		writeQueueErr(w, err, "record contact")
		return
	}
	response.NoContent(w)
}

type promiseRequest struct {
	Date string `json:"date"` // YYYY-MM-DD
	Note string `json:"note"`
}

// RecordPromise godoc
// @Summary      Record a date the member agreed to pay by
// @Tags         queues
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path  int             true  "Payment ID"
// @Param        body  body  promiseRequest  true  "Promise"
// @Success      204
// @Router       /api/v1/payments/{id}/promise [post]
func (h *Handler) RecordPromise(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}

	var req promiseRequest
	if !decode(w, r, &req) {
		return
	}

	on, err := time.ParseInLocation("2006-01-02", strings.TrimSpace(req.Date), IST)
	if err != nil {
		response.BadRequest(w, "date must be in YYYY-MM-DD format")
		return
	}

	if err := h.svc.RecordPromise(r.Context(), id, on, req.Note); err != nil {
		writeQueueErr(w, err, "record promise")
		return
	}
	response.NoContent(w)
}

type settleRequest struct {
	PaymentMode     string `json:"payment_mode"`
	ReferenceNumber string `json:"reference_number"`
}

// Settle godoc
// @Summary      Take the money for a due that already exists
// @Description  Settles the existing pending payment rather than creating a second row for the same money.
// @Tags         queues
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path  int            true  "Payment ID"
// @Param        body  body  settleRequest  true  "Payment"
// @Success      204
// @Router       /api/v1/payments/{id}/settle [post]
func (h *Handler) Settle(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}

	var req settleRequest
	if !decode(w, r, &req) {
		return
	}

	err := h.svc.Settle(r.Context(), id, req.PaymentMode, req.ReferenceNumber)
	if err != nil {
		writeQueueErr(w, err, "settle")
		return
	}
	response.NoContent(w)
}

type writeOffRequest struct {
	Reason string `json:"reason"`
}

// WriteOff godoc
// @Summary      Give up on a due
// @Description  Owner only. Requires a reason — the money stops being receivable.
// @Tags         queues
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path  int              true  "Payment ID"
// @Param        body  body  writeOffRequest  true  "Reason"
// @Success      204
// @Router       /api/v1/payments/{id}/write-off [post]
func (h *Handler) WriteOff(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}

	var req writeOffRequest
	if !decode(w, r, &req) {
		return
	}

	if err := h.svc.WriteOff(r.Context(), id, req.Reason); err != nil {
		writeQueueErr(w, err, "write off")
		return
	}
	response.NoContent(w)
}

func pathID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || id <= 0 {
		response.BadRequest(w, "invalid payment id")
		return 0, false
	}
	return id, true
}

func decode(w http.ResponseWriter, r *http.Request, dst interface{}) bool {
	if err := json.NewDecoder(r.Body).Decode(dst); err != nil {
		response.BadRequest(w, "invalid request body")
		return false
	}
	return true
}

// Each failure gets the message that names what was wrong. "Invalid request"
// would leave the caller guessing which of four things it was.
func writeQueueErr(w http.ResponseWriter, err error, what string) {
	switch {
	case errors.Is(err, ErrNotFound):
		response.NotFound(w, "payment not found")
	case errors.Is(err, ErrOwnerOnly):
		response.Forbidden(w, "only an owner can write off a due")
	case errors.Is(err, ErrReasonRequired):
		response.BadRequest(w, "a write-off needs a reason")
	case errors.Is(err, ErrPastPromise):
		response.BadRequest(w, "the promised date cannot be in the past")
	case errors.Is(err, ErrNotOutstanding):
		response.BadRequest(w, "that due is already settled or written off")
	case errors.Is(err, ErrBadMode):
		response.BadRequest(w, "payment mode must be cash, upi, credit_card, debit_card or bank_transfer")
	default:
		log.Printf("queues: %s: %v", what, err)
		response.InternalServerError(w)
	}
}

type raiseDueRequest struct {
	MemberID      int64  `json:"member_id"`
	PlanID        *int64 `json:"plan_id"`
	AmountInPaise int64  `json:"amount_in_paise"`
	DueDate       string `json:"due_date"` // YYYY-MM-DD, required
	Notes         string `json:"notes"`
}

// RaiseDue godoc
// @Summary      Record that a member owes money
// @Description  Creates a pending payment. Distinct from POST /api/v1/payments, which only ever writes a paid row.
// @Tags         queues
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body  raiseDueRequest  true  "Due"
// @Success      201
// @Router       /api/v1/payments/due [post]
func (h *Handler) RaiseDue(w http.ResponseWriter, r *http.Request) {
	var req raiseDueRequest
	if !decode(w, r, &req) {
		return
	}

	if req.MemberID <= 0 {
		response.BadRequest(w, "member_id is required")
		return
	}

	// Required, never defaulted. Every group in the queue is computed from the
	// due date, and inventing one would bury a real data problem.
	due, err := time.ParseInLocation("2006-01-02", strings.TrimSpace(req.DueDate), IST)
	if err != nil {
		response.BadRequest(w, "due_date is required, in YYYY-MM-DD format")
		return
	}

	id, err := h.svc.RaiseDue(
		r.Context(), req.MemberID, req.PlanID, req.AmountInPaise, due, req.Notes)
	if err != nil {
		switch {
		case errors.Is(err, ErrBadAmount):
			response.BadRequest(w, "amount must be more than zero")
		case errors.Is(err, ErrMemberNotFound):
			response.NotFound(w, "member not found")
		default:
			log.Printf("queues: raise due: %v", err)
			response.InternalServerError(w)
		}
		return
	}
	response.Created(w, map[string]int64{"id": id})
}
