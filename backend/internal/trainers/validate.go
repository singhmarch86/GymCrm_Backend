package trainers

import "strings"

func validCommission(pct *float64) bool {
	return pct == nil || (*pct >= 0 && *pct <= 100)
}

func validateCreate(req CreateTrainerRequest) error {
	if strings.TrimSpace(req.FirstName) == "" || strings.TrimSpace(req.LastName) == "" {
		return ErrNameRequired
	}
	if strings.TrimSpace(req.Phone) == "" {
		return ErrPhoneRequired
	}
	if !validCommission(req.CommissionPct) {
		return ErrInvalidCommission
	}
	return nil
}

func validateUpdate(req UpdateTrainerRequest) error {
	if req.FirstName != nil && strings.TrimSpace(*req.FirstName) == "" {
		return ErrNameRequired
	}
	if req.LastName != nil && strings.TrimSpace(*req.LastName) == "" {
		return ErrNameRequired
	}
	if req.Phone != nil && strings.TrimSpace(*req.Phone) == "" {
		return ErrPhoneRequired
	}
	if !validCommission(req.CommissionPct) {
		return ErrInvalidCommission
	}
	return nil
}
