package payments

import "time"

// ─── Request DTOs ─────────────────────────────────────────────────────────────

// CollectPaymentRequest is the payload for POST /api/v1/payments.
// gym_id and collected_by_user_id are never accepted here — always from JWT.
// @Description Collect a payment from a member. Triggers ONE atomic
// transaction: payment saved, renewal created, member expiry updated.
type CollectPaymentRequest struct {
	MemberID        int64  `json:"member_id"`         // required
	PlanID          int64  `json:"plan_id"`           // required, must be active
	AmountInPaise   int64  `json:"amount_in_paise"`   // required, > 0
	PaymentMode     string `json:"payment_mode"`      // required: cash | upi | credit_card | debit_card | bank_transfer
	PaymentDate     string `json:"payment_date"`      // optional, YYYY-MM-DD, defaults to today
	ReferenceNumber string `json:"reference_number"`  // optional — UPI/bank transaction ref
	Notes           string `json:"notes"`             // optional
}

// ListPaymentsRequest holds query params for GET /api/v1/payments.
type ListPaymentsRequest struct {
	Page     int
	PerPage  int
	Status   string // "" | paid | pending | overdue
	Search   string // matches member first/last name or phone
	DateFrom *time.Time
	DateTo   *time.Time
}

// ─── Response DTOs ────────────────────────────────────────────────────────────

// PaymentResponse is the full payment record, denormalised with member and
// plan display fields — same convention as renewals.RenewalResponse.
// @Description Full payment record.
type PaymentResponse struct {
	ID                 int64      `json:"id"`
	GymID              int64      `json:"gym_id"`
	MemberID           int64      `json:"member_id"`
	MemberName         string     `json:"member_name"`
	Phone              string     `json:"phone"`
	PlanID             *int64     `json:"plan_id,omitempty"`
	PlanName           *string    `json:"plan_name,omitempty"`
	AmountInPaise      int64      `json:"amount_in_paise"`
	AmountInRupees     float64    `json:"amount_in_rupees"` // display only
	Status             string     `json:"status"`           // paid | pending | overdue
	PaymentMode        *string    `json:"payment_mode,omitempty"`
	DueDate            *time.Time `json:"due_date,omitempty"`
	PaidDate           *time.Time `json:"paid_date,omitempty"`
	CollectedByUserID  *int64     `json:"collected_by_user_id,omitempty"`
	ReferenceNumber    *string    `json:"reference_number,omitempty"`
	Notes              *string    `json:"notes,omitempty"`
	CreatedAt          time.Time  `json:"created_at"`
}

// PaymentListResponse wraps a slice of payments.
// @Description Paginated payment list.
type PaymentListResponse struct {
	Payments []PaymentResponse `json:"payments"`
}

// RevenueSummaryResponse backs GET /api/v1/payments/summary — the numbers
// the dashboard Revenue and Payments cards need. See repository.go's
// RevenueSummary doc comment for why this isn't wired into the existing
// dashboard module's DTO in this sprint.
// @Description Revenue and dues summary for the dashboard.
type RevenueSummaryResponse struct {
	TodayRevenueInPaise int64 `json:"today_revenue_in_paise"`
	MonthRevenueInPaise int64 `json:"month_revenue_in_paise"`
	PendingPayments     int64 `json:"pending_payments"`
	CollectedCount      int64 `json:"collected_count"`
}

// ─── Mapper ───────────────────────────────────────────────────────────────────

// overdueGraceDays — a "pending" payment becomes "overdue" in API responses
// once its due_date has passed. Computed at read time, never stored — same
// pattern as members.ExpiryStatus in Sprint 3.
func effectiveStatus(p *PaymentWithContext, today time.Time) string {
	if p.Status == PaymentStatusPending && p.DueDate != nil && p.DueDate.Before(today) {
		return string(PaymentStatusOverdue)
	}
	return string(p.Status)
}

func ToResponse(p *PaymentWithContext, now time.Time) PaymentResponse {
	var mode *string
	if p.PaymentMode != nil {
		s := string(*p.PaymentMode)
		mode = &s
	}

	return PaymentResponse{
		ID:                p.ID,
		GymID:             p.GymID,
		MemberID:          p.MemberID,
		MemberName:        p.MemberFirstName + " " + p.MemberLastName,
		Phone:             p.MemberPhone,
		PlanID:            p.PlanID,
		PlanName:          p.PlanName,
		AmountInPaise:     p.AmountInPaise,
		AmountInRupees:    p.AmountInRupees(),
		Status:            effectiveStatus(p, now),
		PaymentMode:       mode,
		DueDate:           p.DueDate,
		PaidDate:          p.PaidDate,
		CollectedByUserID: p.CollectedByUserID,
		ReferenceNumber:   p.ReferenceNumber,
		Notes:             p.Notes,
		CreatedAt:         p.CreatedAt,
	}
}

func ToResponseList(items []PaymentWithContext, now time.Time) []PaymentResponse {
	out := make([]PaymentResponse, 0, len(items))
	for i := range items {
		out = append(out, ToResponse(&items[i], now))
	}
	return out
}
