package gyms

import (
	"fmt"
	"regexp"
	"strings"
)

// slugPattern matches a public_slug: lowercase letters, digits, and single
// hyphens between them — never a leading/trailing/doubled hyphen, which
// would make for an ugly URL (regulars.app/g/--fitness- is not a page
// anyone should be able to publish).
var slugPattern = regexp.MustCompile(`^[a-z0-9]+(-[a-z0-9]+)*$`)

// ValidateUpdatePublicProfileRequest validates and normalises whichever
// fields the caller actually sent — nil fields (untouched) are skipped
// entirely, matching the request's own partial-update contract.
func ValidateUpdatePublicProfileRequest(req *UpdatePublicProfileRequest) error {
	var errs []string

	if req.PublicSlug != nil {
		slug := strings.ToLower(strings.TrimSpace(*req.PublicSlug))
		req.PublicSlug = &slug
		if len(slug) < 3 || len(slug) > 120 {
			errs = append(errs, "public_slug must be between 3 and 120 characters")
		} else if !slugPattern.MatchString(slug) {
			errs = append(errs, "public_slug may only contain lowercase letters, digits, and single hyphens between them")
		}
	}

	if req.Tagline != nil {
		t := strings.TrimSpace(*req.Tagline)
		req.Tagline = &t
		if len(t) > 200 {
			errs = append(errs, "tagline must not exceed 200 characters")
		}
	}

	if req.Description != nil {
		d := strings.TrimSpace(*req.Description)
		req.Description = &d
	}

	if req.PublicPhone != nil {
		p := strings.TrimSpace(*req.PublicPhone)
		req.PublicPhone = &p
		if len(p) > 20 {
			errs = append(errs, "public_phone must not exceed 20 characters")
		}
	}

	if len(errs) > 0 {
		return fmt.Errorf("%s", strings.Join(errs, "; "))
	}
	return nil
}
