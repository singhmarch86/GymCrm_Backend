package referrals

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
	mux.HandleFunc("POST /api/v1/referrals", h.Create)
	mux.HandleFunc("GET /api/v1/referrals", h.List)
	mux.HandleFunc("POST /api/v1/referrals/{id}/mark-joined", h.MarkJoined)
	mux.HandleFunc("POST /api/v1/referrals/{id}/reward", h.Reward)
	mux.HandleFunc("POST /api/v1/referrals/{id}/expire", h.Expire)
	mux.HandleFunc("GET /api/v1/members/{member_id}/referrals", h.MemberReferrals)
}

// Create godoc
// @Summary      Record a referral
// @Description  Referrer must be an active member.
// @Tags         referrals
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      CreateReferralRequest  true  "Referral details"
// @Success      201   {object}  ReferralResponse
// @Failure      404   {object}  response.Envelope  "Referrer not found"
// @Failure      409   {object}  response.Envelope  "Referrer not active"
// @Router       /api/v1/referrals [post]
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	var req CreateReferralRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.Create(r.Context(), req)
	if err != nil {
		writeErr(w, err, "create referral")
		return
	}
	response.Created(w, res)
}

// List godoc
// @Summary      List referrals
// @Tags         referrals
// @Produce      json
// @Security     BearerAuth
// @Success      200  {array}   ReferralResponse
// @Router       /api/v1/referrals [get]
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	res, err := h.svc.List(r.Context(), nil)
	if err != nil {
		writeErr(w, err, "list referrals")
		return
	}
	response.OK(w, res)
}

// MemberReferrals godoc
// @Summary      A member's own referral history
// @Tags         referrals
// @Produce      json
// @Security     BearerAuth
// @Param        member_id  path      int  true  "Member ID"
// @Success      200  {array}   ReferralResponse
// @Router       /api/v1/members/{member_id}/referrals [get]
func (h *Handler) MemberReferrals(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "member_id")
	if !ok {
		return
	}
	res, err := h.svc.List(r.Context(), &id)
	if err != nil {
		writeErr(w, err, "list member referrals")
		return
	}
	response.OK(w, res)
}

// MarkJoined godoc
// @Summary      Link a referral to the member it produced
// @Tags         referrals
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                 true  "Referral ID"
// @Param        body  body      MarkJoinedRequest   true  "The new member"
// @Success      200   {object}  ReferralResponse
// @Failure      404   {object}  response.Envelope
// @Failure      409   {object}  response.Envelope  "Not pending"
// @Router       /api/v1/referrals/{id}/mark-joined [post]
func (h *Handler) MarkJoined(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	var req MarkJoinedRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.MarkJoined(r.Context(), id, req)
	if err != nil {
		writeErr(w, err, "mark joined")
		return
	}
	response.OK(w, res)
}

// Reward godoc
// @Summary      Reward a joined referral
// @Description  Extends the referrer's expiry_date by reward_days. Never cash, never automatic.
// @Tags         referrals
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int             true  "Referral ID"
// @Param        body  body      RewardRequest   true  "Days to credit"
// @Success      200   {object}  ReferralResponse
// @Failure      404   {object}  response.Envelope
// @Failure      409   {object}  response.Envelope  "Not joined yet, or already rewarded"
// @Router       /api/v1/referrals/{id}/reward [post]
func (h *Handler) Reward(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	var req RewardRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.Reward(r.Context(), id, req)
	if err != nil {
		writeErr(w, err, "reward")
		return
	}
	response.OK(w, res)
}

// Expire godoc
// @Summary      Mark a referral expired
// @Tags         referrals
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Referral ID"
// @Success      200  {object}  ReferralResponse
// @Failure      404  {object}  response.Envelope
// @Failure      409  {object}  response.Envelope  "Already rewarded"
// @Router       /api/v1/referrals/{id}/expire [post]
func (h *Handler) Expire(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r, "id")
	if !ok {
		return
	}
	res, err := h.svc.Expire(r.Context(), id)
	if err != nil {
		writeErr(w, err, "expire")
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
	case errors.Is(err, ErrReferralNotFound), errors.Is(err, ErrReferrerNotFound):
		response.NotFound(w, err.Error())
	case errors.Is(err, ErrReferrerNotActive),
		errors.Is(err, ErrNotPending),
		errors.Is(err, ErrNotJoined),
		errors.Is(err, ErrAlreadyRewarded):
		response.Conflict(w, err.Error())
	case errors.Is(err, ErrReferredNameRequired),
		errors.Is(err, ErrReferredPhoneRequired),
		errors.Is(err, ErrRewardDaysRequired):
		response.UnprocessableEntity(w, err.Error())
	default:
		log.Printf("referrals %s: %v", op, err)
		response.InternalServerError(w)
	}
}
