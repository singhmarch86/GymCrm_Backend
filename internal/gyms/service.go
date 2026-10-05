package gyms

import (
	"context"

	"gymcrm/internal/database"
)

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// GetOwnPublicProfileSettings returns the caller's own gym row, for the
// Flutter settings screen to populate its form from — unlike
// GetPublicProfile, this is allowed to return an unpublished/empty page,
// since the caller is the gym's own staff, not an anonymous visitor.
func (s *Service) GetOwnPublicProfileSettings(ctx context.Context) (*Gym, error) {
	tc := database.MustGetTenant(ctx)
	gym, err := s.repo.GetByID(ctx, tc.GymID())
	if err != nil {
		return nil, err
	}
	if gym == nil {
		return nil, ErrGymNotFound
	}
	return gym, nil
}

// UpdatePublicProfile applies req to the caller's own gym. Owner-only, same
// reasoning as payouts.MarkPaid: this is what makes the gym's name and
// contact details visible to the entire internet, not something any staff
// login should be able to flip on.
func (s *Service) UpdatePublicProfile(ctx context.Context, req UpdatePublicProfileRequest) (*Gym, error) {
	tc := database.MustGetTenant(ctx)
	if !tc.IsOwner() {
		return nil, ErrOwnerOnly
	}

	current, err := s.repo.GetByID(ctx, tc.GymID())
	if err != nil {
		return nil, err
	}
	if current == nil {
		return nil, ErrGymNotFound
	}

	fields := map[string]interface{}{}

	if req.PublicSlug != nil {
		taken, err := s.repo.SlugTaken(ctx, *req.PublicSlug, tc.GymID())
		if err != nil {
			return nil, err
		}
		if taken {
			return nil, ErrSlugTaken
		}
		fields["public_slug"] = *req.PublicSlug
		current.PublicSlug = req.PublicSlug
	}
	if req.Tagline != nil {
		fields["tagline"] = *req.Tagline
		current.Tagline = req.Tagline
	}
	if req.Description != nil {
		fields["public_description"] = *req.Description
		current.PublicDescription = req.Description
	}
	if req.CoverPhoto != nil {
		fields["cover_photo_url"] = *req.CoverPhoto
		current.CoverPhotoURL = req.CoverPhoto
	}
	if req.Amenities != nil {
		fields["amenities"] = req.Amenities
		current.Amenities = req.Amenities
	}
	if req.PublicPhone != nil {
		fields["public_phone"] = *req.PublicPhone
		current.PublicPhone = req.PublicPhone
	}
	if req.Published != nil {
		// A gym can only go live once it actually has a slug — either
		// already stored, or supplied in this same request.
		slug := current.PublicSlug
		if req.PublicSlug != nil {
			slug = req.PublicSlug
		}
		if *req.Published && (slug == nil || *slug == "") {
			return nil, ErrSlugRequired
		}
		fields["published"] = *req.Published
		current.Published = *req.Published
	}

	if err := s.repo.UpdatePublicProfile(ctx, tc.GymID(), fields); err != nil {
		return nil, err
	}
	return current, nil
}
