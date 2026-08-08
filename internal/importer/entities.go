package importer

import (
	"fmt"
	"strings"
	"time"
)

// Per-entity parsing and validation. See docs/FR-05-data-import.md §2 and §3.
//
// Each parser turns one CSV row into a normalised struct, or an error whose
// message a gym owner can act on. Error text names the offending field in
// their language ("phone number is missing"), never ours ("validation failed
// on field phone").

// ─── Members ──────────────────────────────────────────────────────────────────

type memberRow struct {
	FirstName   string     `json:"first_name"`
	LastName    string     `json:"last_name"`
	Phone       string     `json:"phone"`
	Email       *string    `json:"email,omitempty"`
	Gender      *string    `json:"gender,omitempty"`
	DateOfBirth *time.Time `json:"date_of_birth,omitempty"`
	Address     *string    `json:"address,omitempty"`
	PlanName    string     `json:"plan_name,omitempty"`
	StartDate   *time.Time `json:"start_date,omitempty"`
	ExpiryDate  *time.Time `json:"expiry_date,omitempty"`
	Status      string     `json:"status"`
	Notes       *string    `json:"notes,omitempty"`

	// Resolved during validation; nil when the named plan doesn't exist, which
	// is a warning rather than a failure (FR-05 §6.2).
	PlanID      *int64 `json:"plan_id,omitempty"`
	PlanWarning string `json:"plan_warning,omitempty"`
}

var validMemberStatuses = map[string]bool{
	"active": true, "expired": true, "inactive": true, "churned": true,
	"frozen": true, "terminated": true,
}

func parseMemberRow(row []string, h map[string]int) (*memberRow, error) {
	first := cell(row, h, "first_name")
	last := cell(row, h, "last_name")

	// A single "name" column is common; split it rather than rejecting the file.
	if last == "" && strings.Contains(first, " ") {
		first, last = splitName(first)
	}
	if first == "" {
		return nil, fmt.Errorf("first name is missing")
	}

	phone := normalisePhone(cell(row, h, "phone"))
	if phone == "" {
		return nil, fmt.Errorf("phone number is missing")
	}
	if len(phone) < 10 {
		return nil, fmt.Errorf("phone number %q looks too short", cell(row, h, "phone"))
	}

	m := &memberRow{
		FirstName: first,
		LastName:  last,
		Phone:     phone,
		Email:     optional(cell(row, h, "email")),
		Address:   optional(cell(row, h, "address")),
		Notes:     optional(cell(row, h, "notes")),
		PlanName:  cell(row, h, "plan"),
	}

	if g := strings.ToLower(cell(row, h, "gender")); g != "" {
		switch {
		case strings.HasPrefix(g, "m"):
			m.Gender = ptr("male")
		case strings.HasPrefix(g, "f"):
			m.Gender = ptr("female")
		default:
			m.Gender = ptr("other")
		}
	}

	var err error
	if m.DateOfBirth, err = parseDate(cell(row, h, "date_of_birth")); err != nil {
		return nil, fmt.Errorf("date of birth: %w", err)
	}
	if m.StartDate, err = parseDate(cell(row, h, "start_date")); err != nil {
		return nil, fmt.Errorf("start date: %w", err)
	}
	if m.ExpiryDate, err = parseDate(cell(row, h, "expiry_date")); err != nil {
		return nil, fmt.Errorf("expiry date: %w", err)
	}
	if m.StartDate != nil && m.ExpiryDate != nil && m.ExpiryDate.Before(*m.StartDate) {
		return nil, fmt.Errorf("expiry date is before the start date")
	}

	// Status defaults to active and is never inferred from dates — a gym's
	// rules for that are theirs, not ours (FR-05 §7).
	status := strings.ToLower(cell(row, h, "status"))
	if status == "" {
		status = "active"
	}
	if !validMemberStatuses[status] {
		return nil, fmt.Errorf("status %q is not one we recognise", cell(row, h, "status"))
	}
	m.Status = status

	return m, nil
}

// ─── Plans ────────────────────────────────────────────────────────────────────

type planRow struct {
	Name         string  `json:"name"`
	Description  *string `json:"description,omitempty"`
	DurationDays int     `json:"duration_days"`
	PriceInPaise int64   `json:"price_in_paise"`
}

func parsePlanRow(row []string, h map[string]int) (*planRow, error) {
	name := cell(row, h, "first_name") // "name" aliases onto first_name
	if name == "" {
		name = cell(row, h, "plan")
	}
	if name == "" {
		return nil, fmt.Errorf("plan name is missing")
	}

	price, err := parseRupeesToPaise(cell(row, h, "price"))
	if err != nil {
		return nil, fmt.Errorf("price: %w", err)
	}

	days, err := parseInt(cell(row, h, "duration_days"))
	if err != nil {
		return nil, fmt.Errorf("duration: %w", err)
	}
	if days <= 0 {
		return nil, fmt.Errorf("duration in days is missing or zero")
	}

	return &planRow{
		Name:         name,
		Description:  optional(cell(row, h, "description")),
		DurationDays: days,
		PriceInPaise: price,
	}, nil
}

// ─── Payments ─────────────────────────────────────────────────────────────────

type paymentRow struct {
	Phone         string     `json:"phone"`
	AmountInPaise int64      `json:"amount_in_paise"`
	PaymentDate   *time.Time `json:"payment_date,omitempty"`
	PaymentMode   string     `json:"payment_mode"`
	Reference     *string    `json:"reference,omitempty"`
	Notes         *string    `json:"notes,omitempty"`

	// Resolved during validation — a payment with no matching member cannot be
	// imported, since it would be money attached to nobody.
	MemberID int64 `json:"member_id,omitempty"`
}

var paymentModeAliases = map[string]string{
	"cash": "cash", "upi": "upi", "gpay": "upi", "googlepay": "upi", "phonepe": "upi", "paytm": "upi",
	"card": "credit_card", "creditcard": "credit_card", "credit": "credit_card",
	"debitcard": "debit_card", "debit": "debit_card",
	"bank": "bank_transfer", "banktransfer": "bank_transfer", "neft": "bank_transfer",
	"imps": "bank_transfer", "rtgs": "bank_transfer", "cheque": "bank_transfer", "online": "upi",
}

func parsePaymentRow(row []string, h map[string]int) (*paymentRow, error) {
	phone := normalisePhone(cell(row, h, "phone"))
	if phone == "" {
		return nil, fmt.Errorf("member phone number is missing — a payment must belong to someone")
	}

	amount, err := parseRupeesToPaise(cell(row, h, "amount"))
	if err != nil {
		return nil, fmt.Errorf("amount: %w", err)
	}
	if amount <= 0 {
		return nil, fmt.Errorf("amount is missing or zero")
	}

	date, err := parseDate(cell(row, h, "payment_date"))
	if err != nil {
		return nil, fmt.Errorf("payment date: %w", err)
	}

	mode := "cash"
	if raw := normaliseHeader(cell(row, h, "payment_mode")); raw != "" {
		if m, ok := paymentModeAliases[raw]; ok {
			mode = m
		} else {
			// An unknown mode is recorded as cash rather than failing the row —
			// the money is what matters, and the reference field preserves the
			// original wording.
			mode = "cash"
		}
	}

	return &paymentRow{
		Phone:         phone,
		AmountInPaise: amount,
		PaymentDate:   date,
		PaymentMode:   mode,
		Reference:     optional(cell(row, h, "reference")),
		Notes:         optional(cell(row, h, "notes")),
	}, nil
}

// ─── helpers ──────────────────────────────────────────────────────────────────

func optional(s string) *string {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	return &s
}

func ptr[T any](v T) *T { return &v }
