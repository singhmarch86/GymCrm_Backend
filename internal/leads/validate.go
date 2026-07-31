package leads

import (
	"fmt"
	"strings"
	"time"
)

const dateLayout = "2006-01-02"

func ValidateCreateLeadRequest(req *CreateLeadRequest) error {
	var errs []string

	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		errs = append(errs, "name is required")
	}

	req.Phone = strings.TrimSpace(req.Phone)
	if req.Phone == "" {
		errs = append(errs, "phone is required")
	}

	req.Source = strings.TrimSpace(req.Source)
	if req.Source == "" {
		req.Source = "walk_in" // sensible default
	} else if !IsValidSource(req.Source) {
		errs = append(errs, "invalid source — must be one of: walk_in, referral, instagram, facebook, google, whatsapp, website, other")
	}

	req.Email = strings.TrimSpace(req.Email)
	req.Notes = strings.TrimSpace(req.Notes)
	req.Goal = strings.TrimSpace(req.Goal)

	if req.TrialDate != "" {
		if _, err := time.Parse(dateLayout, req.TrialDate); err != nil {
			errs = append(errs, "trial_date must be YYYY-MM-DD")
		}
	}

	if req.FollowUpDate != "" {
		if _, err := time.Parse(dateLayout, req.FollowUpDate); err != nil {
			errs = append(errs, "follow_up_date must be YYYY-MM-DD")
		}
	}

	if len(errs) > 0 {
		return fmt.Errorf("%s", strings.Join(errs, "; "))
	}
	return nil
}

func ValidateAdvanceStatusRequest(req *AdvanceStatusRequest) error {
	req.Status = strings.TrimSpace(req.Status)
	if !IsValidStatus(req.Status) {
		return ErrInvalidStatus
	}
	if req.Status == string(LeadStatusLost) {
		if req.LostReason == nil || strings.TrimSpace(*req.LostReason) == "" {
			return ErrLostReasonRequired
		}
	}
	return nil
}
