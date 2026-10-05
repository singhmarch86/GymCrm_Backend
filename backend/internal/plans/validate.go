package plans

import (
	"fmt"
	"strings"
)

// ValidateCreatePlanRequest validates and normalises the create payload.
// Name is trimmed and stored as-provided — uniqueness is enforced on LOWER(name) at DB level.
func ValidateCreatePlanRequest(req *CreatePlanRequest) error {
	var errs []string

	req.Name = strings.TrimSpace(req.Name)
	req.Description = strings.TrimSpace(req.Description)

	if req.Name == "" {
		errs = append(errs, "name is required")
	} else if len(req.Name) < 2 {
		errs = append(errs, "name must be at least 2 characters")
	} else if len(req.Name) > 200 {
		errs = append(errs, "name must not exceed 200 characters")
	}

	if req.DurationDays <= 0 {
		errs = append(errs, "duration_days must be greater than 0")
	}

	if req.PriceInPaise <= 0 {
		errs = append(errs, "price_in_paise must be greater than 0")
	}

	if len(errs) > 0 {
		return fmt.Errorf("%s", strings.Join(errs, "; "))
	}
	return nil
}

// ValidateUpdatePlanRequest validates the update payload.
func ValidateUpdatePlanRequest(req *UpdatePlanRequest) error {
	var errs []string

	if req.Name != nil {
		*req.Name = strings.TrimSpace(*req.Name)
		if *req.Name == "" {
			errs = append(errs, "name cannot be empty")
		} else if len(*req.Name) < 2 {
			errs = append(errs, "name must be at least 2 characters")
		} else if len(*req.Name) > 200 {
			errs = append(errs, "name must not exceed 200 characters")
		}
	}

	if req.DurationDays != nil && *req.DurationDays <= 0 {
		errs = append(errs, "duration_days must be greater than 0")
	}

	if req.PriceInPaise != nil && *req.PriceInPaise <= 0 {
		errs = append(errs, "price_in_paise must be greater than 0")
	}

	if len(errs) > 0 {
		return fmt.Errorf("%s", strings.Join(errs, "; "))
	}
	return nil
}
