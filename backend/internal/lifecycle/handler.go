package lifecycle

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

// RegisterRoutes mounts all lifecycle endpoints.
// All routes require JWT — the caller wraps them with JWTMiddleware.
func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/members/{id}/freeze", h.Freeze)
	mux.HandleFunc("POST /api/v1/members/{id}/unfreeze", h.Unfreeze)
	mux.HandleFunc("POST /api/v1/members/{id}/upgrade", h.Upgrade)
	mux.HandleFunc("POST /api/v1/members/{id}/transfer", h.Transfer)
	mux.HandleFunc("POST /api/v1/members/{id}/terminate", h.Terminate)

	mux.HandleFunc("GET /api/v1/members/{id}/freeze-eligibility", h.FreezeEligibility)
	mux.HandleFunc("GET /api/v1/members/{id}/upgrade-quote", h.UpgradeQuote)
	mux.HandleFunc("GET /api/v1/members/{id}/termination-quote", h.TerminationQuote)
	mux.HandleFunc("GET /api/v1/members/{id}/lifecycle-events", h.Timeline)
}

// ─── Mutations ────────────────────────────────────────────────────────────────

// Freeze godoc
// @Summary      Freeze a membership
// @Description  Pauses a membership. Expiry extends 1:1 with the frozen duration.
// @Description  Minimum 7 days, maximum 90 per freeze and 90 per membership year.
// @Description  gym_id and performed_by_user_id come from JWT — never from payload.
// @Tags         lifecycle
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int            true  "Member ID"
// @Param        body  body      FreezeRequest  true  "Freeze window"
// @Success      201   {object}  MemberLifecycleResponse
// @Failure      404   {object}  response.Envelope  "Member not found"
// @Failure      409   {object}  response.Envelope  "Already frozen or terminated"
// @Failure      422   {object}  response.Envelope  "Validation error or allowance exhausted"
// @Router       /api/v1/members/{id}/freeze [post]
func (h *Handler) Freeze(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var req FreezeRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.Freeze(r.Context(), id, req)
	if err != nil {
		writeErr(w, err, "freeze")
		return
	}
	response.Created(w, res)
}

// Unfreeze godoc
// @Summary      End a freeze
// @Description  Ends a freeze, possibly early. Ending early pulls expiry back by the
// @Description  unused days and credits them to the member's annual allowance.
// @Tags         lifecycle
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int              true  "Member ID"
// @Param        body  body      UnfreezeRequest  true  "Effective date"
// @Success      201   {object}  MemberLifecycleResponse
// @Failure      404   {object}  response.Envelope
// @Failure      409   {object}  response.Envelope  "Not currently frozen"
// @Router       /api/v1/members/{id}/unfreeze [post]
func (h *Handler) Unfreeze(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var req UnfreezeRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.Unfreeze(r.Context(), id, req)
	if err != nil {
		writeErr(w, err, "unfreeze")
		return
	}
	response.Created(w, res)
}

// Upgrade godoc
// @Summary      Change a member's plan
// @Description  Moves a member to a different plan. Expiry is unchanged; the price
// @Description  difference is prorated across the remaining days. Records the amount
// @Description  owed — it does not collect it.
// @Tags         lifecycle
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int             true  "Member ID"
// @Param        body  body      UpgradeRequest  true  "Target plan"
// @Success      201   {object}  MemberLifecycleResponse
// @Failure      404   {object}  response.Envelope  "Member or plan not found"
// @Failure      409   {object}  response.Envelope  "Frozen, terminated, or already on that plan"
// @Router       /api/v1/members/{id}/upgrade [post]
func (h *Handler) Upgrade(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var req UpgradeRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.Upgrade(r.Context(), id, req)
	if err != nil {
		writeErr(w, err, "upgrade")
		return
	}
	response.Created(w, res)
}

// Transfer godoc
// @Summary      Transfer a membership to another member
// @Description  Moves remaining validity to another member. The source is terminated;
// @Description  the target receives the plan and expiry date. Writes paired
// @Description  transfer_out / transfer_in events.
// @Tags         lifecycle
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int              true  "Source member ID"
// @Param        body  body      TransferRequest  true  "Target member"
// @Success      201   {object}  MemberLifecycleResponse  "State of the receiving member"
// @Failure      404   {object}  response.Envelope
// @Failure      409   {object}  response.Envelope  "Target already has an active membership"
// @Router       /api/v1/members/{id}/transfer [post]
func (h *Handler) Transfer(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var req TransferRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.Transfer(r.Context(), id, req)
	if err != nil {
		writeErr(w, err, "transfer")
		return
	}
	response.Created(w, res)
}

// Terminate godoc
// @Summary      Terminate a membership
// @Description  Ends a membership permanently. Terminal — restoring requires selling a
// @Description  new membership. A reason is required. Any refund is calculated and
// @Description  recorded but never paid out here.
// @Tags         lifecycle
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int               true  "Member ID"
// @Param        body  body      TerminateRequest  true  "Reason and optional fee"
// @Success      201   {object}  MemberLifecycleResponse
// @Failure      404   {object}  response.Envelope
// @Failure      409   {object}  response.Envelope  "Already terminated"
// @Failure      422   {object}  response.Envelope  "Reason missing"
// @Router       /api/v1/members/{id}/terminate [post]
func (h *Handler) Terminate(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var req TerminateRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.Terminate(r.Context(), id, req)
	if err != nil {
		writeErr(w, err, "terminate")
		return
	}
	response.Created(w, res)
}

// ─── Previews and reads ───────────────────────────────────────────────────────

// FreezeEligibility godoc
// @Summary      Check whether a member can be frozen
// @Description  Returns the allowed freeze bounds so the UI can show limits up front
// @Description  rather than rejecting a completed form.
// @Tags         lifecycle
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Member ID"
// @Success      200  {object}  FreezeEligibilityResponse
// @Failure      404  {object}  response.Envelope
// @Router       /api/v1/members/{id}/freeze-eligibility [get]
func (h *Handler) FreezeEligibility(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	res, err := h.svc.FreezeEligibility(r.Context(), id)
	if err != nil {
		writeErr(w, err, "freeze eligibility")
		return
	}
	response.OK(w, res)
}

// UpgradeQuote godoc
// @Summary      Preview the cost of changing plan
// @Description  Returns the prorated amount due (or credit, on a downgrade) without
// @Description  committing the change. Uses the same maths as the upgrade itself.
// @Tags         lifecycle
// @Produce      json
// @Security     BearerAuth
// @Param        id           path      int  true  "Member ID"
// @Param        new_plan_id  query     int  true  "Target plan ID"
// @Success      200  {object}  UpgradeQuoteResponse
// @Failure      404  {object}  response.Envelope
// @Router       /api/v1/members/{id}/upgrade-quote [get]
func (h *Handler) UpgradeQuote(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	planID, err := strconv.ParseInt(r.URL.Query().Get("new_plan_id"), 10, 64)
	if err != nil || planID <= 0 {
		response.BadRequest(w, "new_plan_id is required")
		return
	}
	res, err := h.svc.UpgradeQuote(r.Context(), id, planID)
	if err != nil {
		writeErr(w, err, "upgrade quote")
		return
	}
	response.OK(w, res)
}

// TerminationQuote godoc
// @Summary      Preview the refund on termination
// @Description  Returns the refund owed if the membership were terminated today,
// @Description  net of an optional termination fee. Clamped at zero.
// @Tags         lifecycle
// @Produce      json
// @Security     BearerAuth
// @Param        id           path      int  true  "Member ID"
// @Param        fee_in_paise query     int  false "Termination fee, defaults to 0"
// @Success      200  {object}  TerminationQuoteResponse
// @Failure      404  {object}  response.Envelope
// @Router       /api/v1/members/{id}/termination-quote [get]
func (h *Handler) TerminationQuote(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var fee int64
	if raw := r.URL.Query().Get("fee_in_paise"); raw != "" {
		parsed, err := strconv.ParseInt(raw, 10, 64)
		if err != nil || parsed < 0 {
			response.BadRequest(w, "fee_in_paise must be a non-negative integer")
			return
		}
		fee = parsed
	}
	res, err := h.svc.TerminationQuote(r.Context(), id, fee)
	if err != nil {
		writeErr(w, err, "termination quote")
		return
	}
	response.OK(w, res)
}

// Timeline godoc
// @Summary      Membership lifecycle history
// @Description  Every freeze, unfreeze, plan change, transfer and termination for a
// @Description  member, newest first, with staff attribution.
// @Tags         lifecycle
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Member ID"
// @Success      200  {array}   EventResponse
// @Failure      404  {object}  response.Envelope
// @Router       /api/v1/members/{id}/lifecycle-events [get]
func (h *Handler) Timeline(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	res, err := h.svc.MemberTimeline(r.Context(), id)
	if err != nil {
		writeErr(w, err, "timeline")
		return
	}
	response.OK(w, res)
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

func pathID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || id <= 0 {
		response.BadRequest(w, "invalid member id")
		return 0, false
	}
	return id, true
}

// decode reads a JSON body, tolerating an empty one so that operations whose
// fields are all optional (unfreeze) can be called with no payload at all.
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

// writeErr maps domain errors to HTTP status codes.
//
// 409 is used for "the membership is in the wrong state for this" and 422 for
// "the request itself is out of bounds" — the distinction matters to the client,
// which retries neither but phrases them differently.
func writeErr(w http.ResponseWriter, err error, op string) {
	switch {
	case errors.Is(err, ErrMemberNotFound),
		errors.Is(err, ErrPlanNotFound):
		response.NotFound(w, err.Error())

	case errors.Is(err, ErrAlreadyFrozen),
		errors.Is(err, ErrNotFrozen),
		errors.Is(err, ErrAlreadyTerminated),
		errors.Is(err, ErrSamePlan),
		errors.Is(err, ErrUpgradeWhileFrozen),
		errors.Is(err, ErrTargetHasActive),
		errors.Is(err, ErrNothingToTransfer),
		errors.Is(err, ErrTransferToSelf),
		errors.Is(err, ErrCrossGymTransfer),
		errors.Is(err, ErrCannotFreezeExpiry):
		response.Conflict(w, err.Error())

	case errors.Is(err, ErrFreezeTooShort),
		errors.Is(err, ErrFreezeTooLong),
		errors.Is(err, ErrFreezeAllowanceHit),
		errors.Is(err, ErrPlanInactive),
		errors.Is(err, ErrReasonRequired),
		errors.Is(err, ErrBackdatedTooFar),
		errors.Is(err, ErrFutureDatedTooFar),
		errors.Is(err, ErrFutureDateNotAllowed):
		response.UnprocessableEntity(w, err.Error())

	default:
		// Validation errors from validate.go arrive as plain fmt.Errorf values;
		// they are user-correctable, so surface the message rather than a 500.
		if isValidationErr(err) {
			response.UnprocessableEntity(w, err.Error())
			return
		}
		log.Printf("lifecycle %s: %v", op, err)
		response.InternalServerError(w)
	}
}

// isValidationErr distinguishes user-correctable input errors (which carry no
// wrapped domain sentinel and never came from the repository) from genuine
// failures. Repository and transaction errors are always wrapped with an
// operation prefix by the service, so they contain ": ".
func isValidationErr(err error) bool {
	msg := err.Error()
	for _, marker := range []string{"invalid date", "is required", "cannot be negative", "expected YYYY-MM-DD"} {
		if strings.Contains(msg, marker) {
			return true
		}
	}
	return false
}
