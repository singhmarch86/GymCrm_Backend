package auth

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"

	"gymcrm/internal/database"
	"gymcrm/internal/shared/response"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/auth/register", h.Register)
	mux.HandleFunc("POST /api/v1/auth/login", h.Login)
	mux.HandleFunc("POST /api/v1/auth/refresh", h.Refresh)
}

func (h *Handler) RegisterProtectedRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/auth/me", h.Me)
	mux.HandleFunc("POST /api/v1/auth/logout", h.Logout)
}

// Register godoc
// @Summary      Register a new gym
// @Description  Creates a gym (tenant) and the first owner account atomically.
//               Returns access + refresh tokens — app is immediately usable after registration.
// @Tags         auth
// @Accept       json
// @Produce      json
// @Param        body  body      RegisterGymRequest  true  "Gym and owner details"
// @Success      201   {object}  RegisterResponse
// @Failure      409   {object}  response.Envelope   "Phone already registered"
// @Failure      422   {object}  response.Envelope   "Validation error"
// @Failure      500   {object}  response.Envelope
// @Router       /api/v1/auth/register [post]
func (h *Handler) Register(w http.ResponseWriter, r *http.Request) {
	var req RegisterGymRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "invalid request body")
		return
	}
	if err := ValidateRegisterGymRequest(&req); err != nil {
		response.UnprocessableEntity(w, err.Error())
		return
	}
	result, err := h.svc.RegisterGym(r.Context(), req)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.Created(w, result)
}

// Login godoc
// @Summary      Login with phone and password
// @Tags         auth
// @Accept       json
// @Produce      json
// @Param        body  body      LoginRequest  true  "Credentials"
// @Success      200   {object}  AuthResponse
// @Failure      401   {object}  response.Envelope
// @Failure      403   {object}  response.Envelope
// @Failure      422   {object}  response.Envelope
// @Router       /api/v1/auth/login [post]
func (h *Handler) Login(w http.ResponseWriter, r *http.Request) {
	var req LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "invalid request body")
		return
	}
	if err := ValidateLoginRequest(&req); err != nil {
		response.UnprocessableEntity(w, err.Error())
		return
	}
	result, err := h.svc.Login(r.Context(), req)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, result)
}

// Refresh godoc
// @Summary      Refresh access token
// @Tags         auth
// @Accept       json
// @Produce      json
// @Param        body  body      RefreshRequest  true  "Refresh token"
// @Success      200   {object}  AuthResponse
// @Failure      401   {object}  response.Envelope
// @Router       /api/v1/auth/refresh [post]
func (h *Handler) Refresh(w http.ResponseWriter, r *http.Request) {
	var req RefreshRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "invalid request body")
		return
	}
	if err := ValidateRefreshRequest(&req); err != nil {
		response.UnprocessableEntity(w, err.Error())
		return
	}
	result, err := h.svc.RefreshTokens(r.Context(), req)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, result)
}

// Me godoc
// @Summary      Get current user and gym
// @Tags         auth
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  MeResponse
// @Failure      401  {object}  response.Envelope
// @Router       /api/v1/auth/me [get]
func (h *Handler) Me(w http.ResponseWriter, r *http.Request) {
	tc := database.MustGetTenant(r.Context())
	result, err := h.svc.GetMe(r.Context(), tc.UserID(), tc.GymID())
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, result)
}

// Logout godoc
// @Summary      Logout current user
// @Tags         auth
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  response.Envelope
// @Failure      401  {object}  response.Envelope
// @Router       /api/v1/auth/logout [post]
func (h *Handler) Logout(w http.ResponseWriter, r *http.Request) {
	tc := database.MustGetTenant(r.Context())
	if err := h.svc.Logout(r.Context(), tc.UserID()); err != nil {
		response.InternalServerError(w)
		return
	}
	response.OK(w, map[string]string{"message": "logged out successfully"})
}

// handleError maps domain errors → HTTP status codes.
// Unknown errors are logged with full detail server-side, generic message client-side.
func (h *Handler) handleError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrInvalidCredentials):
		response.Unauthorized(w, "invalid phone or password")
	case errors.Is(err, ErrUserInactive):
		response.Forbidden(w, "account is inactive, contact your gym owner")
	case errors.Is(err, ErrGymInactive):
		response.Forbidden(w, "gym account is inactive")
	case errors.Is(err, ErrGymPhoneAlreadyRegistered):
		response.Conflict(w, "a gym with this phone number is already registered")
	case errors.Is(err, ErrPhoneAlreadyRegistered):
		response.Conflict(w, "this phone number is already registered")
	case errors.Is(err, ErrRefreshTokenInvalid), errors.Is(err, ErrRefreshTokenRevoked):
		response.Unauthorized(w, "refresh token is invalid or expired, please login again")
	default:
		log.Printf("ERROR auth handler: %v", err) // visible in docker compose logs
		response.InternalServerError(w)
	}
}
