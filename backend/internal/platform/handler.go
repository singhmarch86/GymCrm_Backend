package platform

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"

	"gymcrm/internal/database"
	"gymcrm/internal/shared/response"
)

type Handler struct {
	svc       *Service
	gymSecret string
}

func NewHandler(svc *Service, gymSecret string) *Handler {
	return &Handler{svc: svc, gymSecret: gymSecret}
}

type ctxKey struct{}

// requireScope authenticates a platform token of exactly the given scope.
// Session-scope also re-checks the admin is still active and enrolled, so
// disabling an admin cuts them off immediately rather than at token expiry.
func (h *Handler) requireScope(scope string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		hdr := r.Header.Get("Authorization")
		if !strings.HasPrefix(strings.ToLower(hdr), "bearer ") {
			response.Unauthorized(w, "missing platform token")
			return
		}
		c, err := parse(h.svc.secret, strings.TrimSpace(hdr[7:]))
		if err != nil || c.Scope != scope {
			response.Unauthorized(w, "invalid or expired platform token")
			return
		}
		a, err := h.svc.adminByID(r.Context(), c.AdminID)
		if err != nil || a.Status != "active" || (scope == ScopeSession && !a.Enrolled) {
			response.Unauthorized(w, "invalid or expired platform token")
			return
		}
		next(w, r.WithContext(context.WithValue(r.Context(), ctxKey{}, a)))
	}
}

func adminOf(r *http.Request) *Admin { return r.Context().Value(ctxKey{}).(*Admin) }

func (h *Handler) Register(mux *http.ServeMux) {
	s := func(f http.HandlerFunc) http.HandlerFunc { return h.requireScope(ScopeSession, f) }
	e := func(f http.HandlerFunc) http.HandlerFunc { return h.requireScope(ScopeEnroll, f) }

	mux.HandleFunc("POST /api/v1/platform/login", h.login)
	mux.HandleFunc("POST /api/v1/platform/2fa/setup", e(h.setup))
	mux.HandleFunc("POST /api/v1/platform/2fa/confirm", e(h.confirm))

	mux.HandleFunc("GET /api/v1/platform/me", s(func(w http.ResponseWriter, r *http.Request) { response.OK(w, adminOf(r)) }))
	mux.HandleFunc("GET /api/v1/platform/gyms", s(h.listGyms))
	mux.HandleFunc("POST /api/v1/platform/gyms", s(h.createGym))
	mux.HandleFunc("GET /api/v1/platform/gyms/{id}", s(h.gymSummary))
	mux.HandleFunc("PATCH /api/v1/platform/gyms/{id}", s(h.patchGym))
	mux.HandleFunc("POST /api/v1/platform/gyms/{id}/suspend", s(h.suspend))
	mux.HandleFunc("POST /api/v1/platform/gyms/{id}/resume", s(h.resume))
	mux.HandleFunc("POST /api/v1/platform/gyms/{id}/enter", s(h.enter))
	mux.HandleFunc("GET /api/v1/platform/access-log", s(h.accessLog))
	mux.HandleFunc("GET /api/v1/platform/admins", s(h.listAdmins))
	mux.HandleFunc("POST /api/v1/platform/admins", s(h.createAdmin))
	mux.HandleFunc("POST /api/v1/platform/admins/{id}/reset", s(h.resetAdmin))
}

// SupportHistory is the gym-side half (§6): an owner lists every vendor entry.
func (h *Handler) SupportHistory(w http.ResponseWriter, r *http.Request) {
	tc := database.MustGetTenant(r.Context())
	if !tc.IsOwner() {
		response.Forbidden(w, "owner access required")
		return
	}
	out, err := h.svc.GymSupportHistory(r.Context(), tc.GymID())
	if err != nil {
		h.fail(w, err)
		return
	}
	response.OK(w, out)
}

func (h *Handler) fail(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrBadCredentials):
		response.Unauthorized(w, err.Error())
	case errors.Is(err, ErrLocked):
		response.JSON(w, http.StatusTooManyRequests, map[string]any{"success": false, "error": map[string]string{"code": "TOO_MANY_ATTEMPTS", "message": err.Error()}})
	case errors.Is(err, ErrNotFound):
		response.NotFound(w, "not found")
	case errors.Is(err, ErrInvalid):
		response.UnprocessableEntity(w, err.Error())
	case errors.Is(err, ErrConflict):
		response.Conflict(w, err.Error())
	default:
		log.Printf("ERROR platform: %v", err)
		response.InternalServerError(w)
	}
}

func decode(w http.ResponseWriter, r *http.Request, v any) bool {
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<16)).Decode(v); err != nil {
		response.BadRequest(w, "invalid JSON body")
		return false
	}
	return true
}

func pathID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || id <= 0 {
		response.BadRequest(w, "invalid id")
		return 0, false
	}
	return id, true
}

func (h *Handler) login(w http.ResponseWriter, r *http.Request) {
	var raw struct {
		Email        string `json:"email"`
		Password     string `json:"password"`
		Code         string `json:"code"`
		RecoveryCode string `json:"recovery_code"`
	}
	if !decode(w, r, &raw) {
		return
	}
	res, err := h.svc.Login(r.Context(), raw.Email, raw.Password, raw.Code, raw.RecoveryCode)
	if err != nil {
		h.fail(w, err)
		return
	}
	response.OK(w, res)
}

func (h *Handler) setup(w http.ResponseWriter, r *http.Request) {
	out, err := h.svc.StartEnrolment(r.Context(), adminOf(r).ID)
	if err != nil {
		h.fail(w, err)
		return
	}
	response.OK(w, out)
}

func (h *Handler) confirm(w http.ResponseWriter, r *http.Request) {
	var b struct {
		Code string `json:"code"`
	}
	if !decode(w, r, &b) {
		return
	}
	out, err := h.svc.ConfirmEnrolment(r.Context(), adminOf(r).ID, b.Code)
	if err != nil {
		h.fail(w, err)
		return
	}
	response.OK(w, out)
}

func (h *Handler) listGyms(w http.ResponseWriter, r *http.Request) {
	out, err := h.svc.ListGyms(r.Context())
	if err != nil {
		h.fail(w, err)
		return
	}
	response.OK(w, out)
}

func (h *Handler) gymSummary(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	out, err := h.svc.GymSummary(r.Context(), id)
	if err != nil {
		h.fail(w, err)
		return
	}
	response.OK(w, out)
}

func (h *Handler) createGym(w http.ResponseWriter, r *http.Request) {
	var in CreateGymInput
	if !decode(w, r, &in) {
		return
	}
	out, err := h.svc.CreateGym(r.Context(), adminOf(r).ID, in)
	if err != nil {
		h.fail(w, err)
		return
	}
	response.Created(w, out)
}

func (h *Handler) patchGym(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var b struct {
		PlanTier           *string `json:"plan_tier"`
		SubscriptionStatus *string `json:"subscription_status"`
	}
	if !decode(w, r, &b) {
		return
	}
	a := adminOf(r)
	if b.PlanTier != nil {
		if err := h.svc.SetPlan(r.Context(), a.ID, id, *b.PlanTier); err != nil {
			h.fail(w, err)
			return
		}
	}
	if b.SubscriptionStatus != nil {
		if err := h.svc.SetSubscription(r.Context(), a.ID, id, *b.SubscriptionStatus); err != nil {
			h.fail(w, err)
			return
		}
	}
	h.gymSummary(w, r)
}

func (h *Handler) suspend(w http.ResponseWriter, r *http.Request) { h.suspendOrResume(w, r, true) }
func (h *Handler) resume(w http.ResponseWriter, r *http.Request)  { h.suspendOrResume(w, r, false) }

func (h *Handler) suspendOrResume(w http.ResponseWriter, r *http.Request, suspend bool) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var b struct {
		Reason string `json:"reason"`
	}
	if !decode(w, r, &b) {
		return
	}
	var err error
	if suspend {
		err = h.svc.Suspend(r.Context(), adminOf(r).ID, id, b.Reason)
	} else {
		err = h.svc.Resume(r.Context(), adminOf(r).ID, id, b.Reason)
	}
	if err != nil {
		h.fail(w, err)
		return
	}
	h.gymSummary(w, r)
}

func (h *Handler) enter(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var b struct {
		Reason string `json:"reason"`
	}
	if !decode(w, r, &b) {
		return
	}
	out, err := h.svc.EnterGym(r.Context(), adminOf(r).ID, id, b.Reason, h.gymSecret)
	if err != nil {
		h.fail(w, err)
		return
	}
	response.OK(w, out)
}

func (h *Handler) accessLog(w http.ResponseWriter, r *http.Request) {
	gym, _ := strconv.ParseInt(r.URL.Query().Get("gym_id"), 10, 64)
	adm, _ := strconv.ParseInt(r.URL.Query().Get("admin_id"), 10, 64)
	acc, act, err := h.svc.AccessLog(r.Context(), gym, adm)
	if err != nil {
		h.fail(w, err)
		return
	}
	response.OK(w, map[string]any{"support_access": acc, "actions": act})
}

func (h *Handler) listAdmins(w http.ResponseWriter, r *http.Request) {
	out, err := h.svc.ListAdmins(r.Context())
	if err != nil {
		h.fail(w, err)
		return
	}
	response.OK(w, out)
}

func (h *Handler) createAdmin(w http.ResponseWriter, r *http.Request) {
	var raw struct {
		Email string `json:"email"`
		Name  string `json:"name"`
	}
	if !decode(w, r, &raw) {
		return
	}
	a, pw, err := h.svc.CreateAdmin(r.Context(), adminOf(r).ID, raw.Email, raw.Name)
	if err != nil {
		h.fail(w, err)
		return
	}
	response.Created(w, map[string]any{"admin": a, "temporary_password": pw})
}

func (h *Handler) resetAdmin(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	pw, err := h.svc.ResetAdmin(r.Context(), adminOf(r).ID, id)
	if err != nil {
		h.fail(w, err)
		return
	}
	response.OK(w, map[string]string{"temporary_password": pw})
}
