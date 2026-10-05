package payments

import (
	"fmt"
	"strings"
	"time"
)

const dateLayout = "2006-01-02"

// ValidateCollectPaymentRequest validates the Collect Payment payload.
func ValidateCollectPaymentRequest(req *CollectPaymentRequest) error {
	var errs []string

	if req.MemberID <= 0 {
		errs = append(errs, "member_id is required")
	}
	if req.PlanID <= 0 {
		errs = append(errs, "plan_id is required")
	}
	if req.AmountInPaise <= 0 {
		errs = append(errs, "amount_in_paise must be greater than 0")
	}

	req.PaymentMode = strings.TrimSpace(req.PaymentMode)
	if req.PaymentMode == "" {
		errs = append(errs, "payment_mode is required")
	} else if !IsValidPaymentMode(req.PaymentMode) {
		errs = append(errs, "payment_mode must be one of: cash, upi, credit_card, debit_card, bank_transfer")
	}

	req.PaymentDate = strings.TrimSpace(req.PaymentDate)
	if req.PaymentDate != "" {
		if _, err := time.Parse(dateLayout, req.PaymentDate); err != nil {
			errs = append(errs, "payment_date must be in YYYY-MM-DD format")
		}
	}

	req.ReferenceNumber = strings.TrimSpace(req.ReferenceNumber)
	req.Notes = strings.TrimSpace(req.Notes)

	if len(errs) > 0 {
		return fmt.Errorf("%s", strings.Join(errs, "; "))
	}
	return nil
}
