package gyms

// UpdatePublicProfileRequest is the payload for
// PATCH /api/v1/gyms/public-profile — a partial update, mirroring
// UpdatePlanRequest's shape: every field is a pointer, and a nil field
// means "leave this alone," not "clear it." Published is the one
// exception (a plain bool) since there's no meaningful "leave publish
// state alone" default for a request that's only ever sent from one
// settings screen that always knows the toggle's current position.
type UpdatePublicProfileRequest struct {
	PublicSlug  *string  `json:"public_slug"`
	Tagline     *string  `json:"tagline"`
	Description *string  `json:"description"`
	CoverPhoto  *string  `json:"cover_photo_url"`
	Amenities   []string `json:"amenities"`
	PublicPhone *string  `json:"public_phone"`
	Published   *bool    `json:"published"`
}

// publicProfileSettingsResponse echoes back the full editable state after a
// save, plus the URL the gym owner actually shares — the Flutter settings
// screen renders this directly rather than re-deriving the URL itself.
type publicProfileSettingsResponse struct {
	publicProfileResponse
	PublicSlug string `json:"public_slug,omitempty"`
	Published  bool   `json:"published"`
	PageURL    string `json:"page_url,omitempty"`
}

func toPublicProfileSettingsResponse(g *Gym, baseURL string) publicProfileSettingsResponse {
	resp := publicProfileSettingsResponse{
		publicProfileResponse: toPublicProfileResponse(g),
		PublicSlug:            deref(g.PublicSlug),
		Published:             g.Published,
	}
	if resp.PublicSlug != "" {
		resp.PageURL = baseURL + "/g/" + resp.PublicSlug
	}
	return resp
}
