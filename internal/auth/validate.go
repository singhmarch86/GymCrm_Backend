package auth

import (
	"fmt"
	"regexp"
	"strings"
	"unicode"
)

// phoneRegex matches Indian mobile numbers: 10 digits, optionally prefixed with +91
var phoneRegex = regexp.MustCompile(`^(\+91)?[6-9]\d{9}$`)

// ValidateRegisterGymRequest validates the registration payload.
// Returns a human-readable error string suitable for the API response.
// Using manual validation instead of a library to keep dependencies lean.
func ValidateRegisterGymRequest(req *RegisterGymRequest) error {
	var errs []string

	req.GymName = strings.TrimSpace(req.GymName)
	req.OwnerName = strings.TrimSpace(req.OwnerName)
	req.Phone = strings.TrimSpace(req.Phone)
	req.City = strings.TrimSpace(req.City)
	req.State = strings.TrimSpace(req.State)
	req.Email = strings.TrimSpace(req.Email)

	if req.GymName == "" {
		errs = append(errs, "gym_name is required")
	} else if len(req.GymName) < 2 || len(req.GymName) > 200 {
		errs = append(errs, "gym_name must be between 2 and 200 characters")
	}

	if req.OwnerName == "" {
		errs = append(errs, "owner_name is required")
	} else if len(req.OwnerName) < 2 || len(req.OwnerName) > 200 {
		errs = append(errs, "owner_name must be between 2 and 200 characters")
	}

	if req.Phone == "" {
		errs = append(errs, "phone is required")
	} else if !phoneRegex.MatchString(req.Phone) {
		errs = append(errs, "phone must be a valid Indian mobile number")
	}

	if req.Password == "" {
		errs = append(errs, "password is required")
	} else if err := validatePassword(req.Password); err != nil {
		errs = append(errs, err.Error())
	}

	if req.City == "" {
		errs = append(errs, "city is required")
	}
	if req.State == "" {
		errs = append(errs, "state is required")
	}

	if req.Email != "" && !isValidEmail(req.Email) {
		errs = append(errs, "email is not valid")
	}

	if len(errs) > 0 {
		return fmt.Errorf("%s", strings.Join(errs, "; "))
	}
	return nil
}

// ValidateLoginRequest validates the login payload.
func ValidateLoginRequest(req *LoginRequest) error {
	req.Phone = strings.TrimSpace(req.Phone)

	if req.Phone == "" {
		return fmt.Errorf("phone is required")
	}
	if !phoneRegex.MatchString(req.Phone) {
		return fmt.Errorf("phone must be a valid Indian mobile number")
	}
	if req.Password == "" {
		return fmt.Errorf("password is required")
	}
	return nil
}

// ValidateRefreshRequest validates the refresh token payload.
func ValidateRefreshRequest(req *RefreshRequest) error {
	req.RefreshToken = strings.TrimSpace(req.RefreshToken)
	if req.RefreshToken == "" {
		return fmt.Errorf("refresh_token is required")
	}
	return nil
}

// ─── Private helpers ──────────────────────────────────────────────────────────

// validatePassword enforces minimum password requirements.
// Deliberately simple — gym owners in Punjab value usability over complexity.
func validatePassword(p string) error {
	if len(p) < 8 {
		return fmt.Errorf("password must be at least 8 characters")
	}
	if len(p) > 72 {
		// bcrypt silently truncates at 72 bytes — we reject instead
		return fmt.Errorf("password must not exceed 72 characters")
	}
	hasDigit := false
	for _, r := range p {
		if unicode.IsDigit(r) {
			hasDigit = true
			break
		}
	}
	if !hasDigit {
		return fmt.Errorf("password must contain at least one digit")
	}
	return nil
}

// isValidEmail performs a basic structural email check.
// Not RFC 5322 compliant — just catches obvious typos.
func isValidEmail(e string) bool {
	parts := strings.Split(e, "@")
	if len(parts) != 2 {
		return false
	}
	if len(parts[0]) == 0 || len(parts[1]) == 0 {
		return false
	}
	if !strings.Contains(parts[1], ".") {
		return false
	}
	return true
}
