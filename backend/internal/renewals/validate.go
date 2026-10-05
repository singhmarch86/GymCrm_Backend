package renewals

import (
	"fmt"
	"strings"
	"time"
)

const dateLayout = "2006-01-02"

// ValidateCreateRenewalRequest validates the renewal creation payload.
func ValidateCreateRenewalRequest(req *CreateRenewalRequest) error {
	var errs []string

	if req.MemberID <= 0 {
		errs = append(errs, "member_id is required")
	}
	if req.PlanID <= 0 {
		errs = append(errs, "plan_id is required")
	}
	if req.AmountPaidInPaise <= 0 {
		errs = append(errs, "amount_paid_in_paise must be greater than 0")
	}

	req.RenewalDate = strings.TrimSpace(req.RenewalDate)
	if req.RenewalDate != "" {
		if _, err := time.Parse(dateLayout, req.RenewalDate); err != nil {
			errs = append(errs, "renewal_date must be in YYYY-MM-DD format")
		}
	}

	req.Notes = strings.TrimSpace(req.Notes)

	if len(errs) > 0 {
		return fmt.Errorf("%s", strings.Join(errs, "; "))
	}
	return nil
}
