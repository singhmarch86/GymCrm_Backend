package members

import (
	"fmt"
	"regexp"
	"strings"
	"time"
)

var phoneRegex = regexp.MustCompile(`^(\+91)?[6-9]\d{9}$`)

const dateLayout = "2006-01-02"

// ValidateCreateMemberRequest validates and normalises the create payload.
func ValidateCreateMemberRequest(req *CreateMemberRequest) error {
	var errs []string

	req.FirstName = strings.TrimSpace(req.FirstName)
	req.LastName  = strings.TrimSpace(req.LastName)
	req.Phone     = strings.TrimSpace(req.Phone)
	req.Email     = strings.TrimSpace(req.Email)
	req.Address   = strings.TrimSpace(req.Address)
	req.Notes     = strings.TrimSpace(req.Notes)

	if req.FirstName == "" {
		errs = append(errs, "first_name is required")
	} else if len(req.FirstName) < 2 || len(req.FirstName) > 100 {
		errs = append(errs, "first_name must be between 2 and 100 characters")
	}

	if req.LastName == "" {
		errs = append(errs, "last_name is required")
	} else if len(req.LastName) > 100 {
		errs = append(errs, "last_name must not exceed 100 characters")
	}

	if req.Phone == "" {
		errs = append(errs, "phone is required")
	} else if !phoneRegex.MatchString(req.Phone) {
		errs = append(errs, "phone must be a valid Indian mobile number")
	}

	if req.Email != "" && !isValidEmail(req.Email) {
		errs = append(errs, "email is not valid")
	}

	if req.Gender != "" {
		switch req.Gender {
		case "male", "female", "other":
		default:
			errs = append(errs, "gender must be one of: male, female, other")
		}
	}

	if req.DateOfBirth != "" {
		if _, err := time.Parse(dateLayout, req.DateOfBirth); err != nil {
			errs = append(errs, "date_of_birth must be in YYYY-MM-DD format")
		}
	}

	var startDate, expiryDate time.Time
	var startParsed, expiryParsed bool

	if req.StartDate != "" {
		t, err := time.Parse(dateLayout, req.StartDate)
		if err != nil {
			errs = append(errs, "start_date must be in YYYY-MM-DD format")
		} else {
			startDate = t
			startParsed = true
		}
	}

	if req.ExpiryDate != "" {
		t, err := time.Parse(dateLayout, req.ExpiryDate)
		if err != nil {
			errs = append(errs, "expiry_date must be in YYYY-MM-DD format")
		} else {
			expiryDate = t
			expiryParsed = true
		}
	}

	// Cross-field: expiry must be after start
	if startParsed && expiryParsed && !expiryDate.After(startDate) {
		errs = append(errs, "expiry_date must be after start_date")
	}

	if len(errs) > 0 {
		return fmt.Errorf("%s", strings.Join(errs, "; "))
	}
	return nil
}

// ValidateUpdateMemberRequest validates the update payload.
func ValidateUpdateMemberRequest(req *UpdateMemberRequest) error {
	var errs []string

	if req.FirstName != nil {
		*req.FirstName = strings.TrimSpace(*req.FirstName)
		if len(*req.FirstName) < 2 || len(*req.FirstName) > 100 {
			errs = append(errs, "first_name must be between 2 and 100 characters")
		}
	}

	if req.LastName != nil {
		*req.LastName = strings.TrimSpace(*req.LastName)
		if len(*req.LastName) > 100 {
			errs = append(errs, "last_name must not exceed 100 characters")
		}
	}

	if req.Phone != nil {
		*req.Phone = strings.TrimSpace(*req.Phone)
		if !phoneRegex.MatchString(*req.Phone) {
			errs = append(errs, "phone must be a valid Indian mobile number")
		}
	}

	if req.Email != nil {
		*req.Email = strings.TrimSpace(*req.Email)
		if *req.Email != "" && !isValidEmail(*req.Email) {
			errs = append(errs, "email is not valid")
		}
	}

	if req.Gender != nil {
		switch *req.Gender {
		case "male", "female", "other":
		default:
			errs = append(errs, "gender must be one of: male, female, other")
		}
	}

	if req.Status != nil {
		switch *req.Status {
		case "active", "expired", "inactive", "churned":
		default:
			errs = append(errs, "status must be one of: active, expired, inactive, churned")
		}
	}

	var startDate, expiryDate time.Time
	var startParsed, expiryParsed bool

	if req.StartDate != nil {
		t, err := time.Parse(dateLayout, *req.StartDate)
		if err != nil {
			errs = append(errs, "start_date must be in YYYY-MM-DD format")
		} else {
			startDate = t
			startParsed = true
		}
	}

	if req.ExpiryDate != nil {
		t, err := time.Parse(dateLayout, *req.ExpiryDate)
		if err != nil {
			errs = append(errs, "expiry_date must be in YYYY-MM-DD format")
		} else {
			expiryDate = t
			expiryParsed = true
		}
	}

	if startParsed && expiryParsed && !expiryDate.After(startDate) {
		errs = append(errs, "expiry_date must be after start_date")
	}

	if len(errs) > 0 {
		return fmt.Errorf("%s", strings.Join(errs, "; "))
	}
	return nil
}

func isValidEmail(e string) bool {
	parts := strings.Split(e, "@")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return false
	}
	return strings.Contains(parts[1], ".")
}
