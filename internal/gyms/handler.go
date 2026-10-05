package gyms

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"

	"gymcrm/internal/shared/response"
)

type Handler struct {
	repo    *Repository
	svc     *Service
	baseURL string
}

func NewHandler(repo *Repository, svc *Service, baseURL string) *Handler {
	return &Handler{repo: repo, svc: svc, baseURL: baseURL}
}

// publicProfileResponse is deliberately its own type, not the Gym struct
// directly — Gym also carries Phone/Address/OwnerName/Status, none of
// which belong on a page anyone on the internet can load. Only the fields
// a gym owner explicitly wrote for this page are exposed.
type publicProfileResponse struct {
	Name        string   `json:"name"`
	Tagline     string   `json:"tagline,omitempty"`
	Description string   `json:"description,omitempty"`
	CoverPhoto  string   `json:"cover_photo_url,omitempty"`
	Amenities   []string `json:"amenities,omitempty"`
	City        string   `json:"city"`
	State       string   `json:"state"`
	Phone       string   `json:"phone,omitempty"`
}

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

func toPublicProfileResponse(g *Gym) publicProfileResponse {
	return publicProfileResponse{
		Name:        g.Name,
		Tagline:     deref(g.Tagline),
		Description: deref(g.PublicDescription),
		CoverPhoto:  deref(g.CoverPhotoURL),
		Amenities:   g.Amenities,
		City:        g.City,
		State:       g.State,
		Phone:       deref(g.PublicPhone),
	}
}

// GetPublicProfile godoc
// @Summary      Public advertisement page for a gym
// @Description  Unauthenticated — anyone with the slug (or a search engine) can read this. Returns 404 for an unpublished or unknown slug, identically, so a slug's existence is never revealed either way.
// @Tags         public
// @Produce      json
// @Param        slug  path  string  true  "public_slug"
// @Success      200  {object}  publicProfileResponse
// @Failure      404
// @Router       /public/gyms/{slug} [get]
func (h *Handler) GetPublicProfile(w http.ResponseWriter, r *http.Request) {
	slug := r.PathValue("slug")
	if slug == "" {
		response.NotFound(w, "gym not found")
		return
	}
	gym, err := h.repo.GetPublicProfile(r.Context(), slug)
	if err != nil {
		log.Printf("gyms.GetPublicProfile: %v", err)
		response.InternalServerError(w)
		return
	}
	if gym == nil {
		response.NotFound(w, "gym not found")
		return
	}
	response.OK(w, toPublicProfileResponse(gym))
}

// GetPublicProfileSettings godoc
// @Summary      The caller's own gym, for the public-page settings screen
// @Description  Owner or staff may read this (matches display-info's own "nothing sensitive here" reasoning) — only UpdatePublicProfile is owner-only.
// @Tags         gyms
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  publicProfileSettingsResponse
// @Router       /api/v1/gyms/public-profile [get]
func (h *Handler) GetPublicProfileSettings(w http.ResponseWriter, r *http.Request) {
	gym, err := h.svc.GetOwnPublicProfileSettings(r.Context())
	if err != nil {
		h.handleError(w, "GetPublicProfileSettings", err)
		return
	}
	response.OK(w, toPublicProfileSettingsResponse(gym, h.baseURL))
}

// UpdatePublicProfile godoc
// @Summary      Edit the gym's public advertisement page
// @Description  Partial update — only the fields sent are changed. Owner only. Publishing (published:true) requires a public_slug already set, or supplied in the same request.
// @Tags         gyms
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      UpdatePublicProfileRequest  true  "Fields to change"
// @Success      200  {object}  publicProfileSettingsResponse
// @Failure      403  {object}  response.Envelope  "Not the gym owner"
// @Failure      409  {object}  response.Envelope  "public_slug already taken"
// @Failure      422  {object}  response.Envelope  "Validation error, or publishing without a slug"
// @Router       /api/v1/gyms/public-profile [patch]
func (h *Handler) UpdatePublicProfile(w http.ResponseWriter, r *http.Request) {
	var req UpdatePublicProfileRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "invalid request body")
		return
	}
	if err := ValidateUpdatePublicProfileRequest(&req); err != nil {
		response.UnprocessableEntity(w, err.Error())
		return
	}
	gym, err := h.svc.UpdatePublicProfile(r.Context(), req)
	if err != nil {
		h.handleError(w, "UpdatePublicProfile", err)
		return
	}
	response.OK(w, toPublicProfileSettingsResponse(gym, h.baseURL))
}

func (h *Handler) handleError(w http.ResponseWriter, what string, err error) {
	switch {
	case errors.Is(err, ErrOwnerOnly):
		response.Forbidden(w, "only an owner can edit the public page")
	case errors.Is(err, ErrSlugTaken):
		response.Conflict(w, "that page address is already taken")
	case errors.Is(err, ErrSlugRequired):
		response.UnprocessableEntity(w, "set a page address before publishing")
	case errors.Is(err, ErrGymNotFound):
		response.NotFound(w, "gym not found")
	default:
		log.Printf("gyms.%s: %v", what, err)
		response.InternalServerError(w)
	}
}
