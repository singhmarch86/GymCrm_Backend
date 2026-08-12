package pt

import "time"

// ─── Packages ─────────────────────────────────────────────────────────────────

// CreatePackageRequest is the payload for POST /api/v1/pt-packages.
// @Description Sell a PT package to a member.
type CreatePackageRequest struct {
	MemberID      int64  `json:"member_id"`       // required
	TrainerID     int64  `json:"trainer_id"`      // required
	PackageName   string `json:"package_name"`    // required
	TotalSessions int    `json:"total_sessions"`  // required, > 0
	AmountInPaise int64  `json:"amount_in_paise"` // required, >= 0
	ExpiryDate    string `json:"expiry_date"`     // optional, YYYY-MM-DD

	// ── The money (FR-21 §3) ────────────────────────────────────────────
	//
	// Selling a package now always produces a payment row: either paid, or a
	// due that lands in the collections queue. Before this, PT could be sold
	// and no money recorded anywhere — the gym's own data had two packages
	// worth ₹10,000 with no payment against either, and nothing to chase,
	// because no debt had ever been written down.
	//
	// The payment carries pt_package_id, which is what lets commission accrue
	// on money actually received rather than on packages created.

	// Empty means the money was NOT taken: a due is raised instead. Never
	// defaulted to cash — assuming payment for an unpaid package is the exact
	// leak this closes.
	PaymentMode string `json:"payment_mode"` // "" | cash | upi | credit_card | debit_card | bank_transfer

	// Defaults to the full package amount. Less than that is a part payment,
	// and the remainder is raised as a due in the same transaction.
	AmountPaidInPaise int64 `json:"amount_paid_in_paise"`

	// Used for whatever is unpaid. Defaults to today, so an unpaid package
	// appears in collections straight away rather than sitting dateless.
	DueDate string `json:"due_date"` // optional, YYYY-MM-DD

	ReferenceNumber string `json:"reference_number"` // optional
	PaymentNotes    string `json:"payment_notes"`    // optional
}

// UpdatePackageStatusRequest changes a package's status directly — e.g. to
// expired or cancelled. Manual only; nothing expires packages automatically.
// @Description Change a package's status.
type UpdatePackageStatusRequest struct {
	Status string `json:"status"` // required: active | expired | cancelled
}

// PackageResponse is a package with names resolved for display.
// @Description A sold PT package.
type PackageResponse struct {
	ID                int64      `json:"id"`
	MemberID          int64      `json:"member_id"`
	MemberName        string     `json:"member_name"`
	TrainerID         int64      `json:"trainer_id"`
	TrainerName       string     `json:"trainer_name"`
	PackageName       string     `json:"package_name"`
	TotalSessions     int        `json:"total_sessions"`
	SessionsUsed      int        `json:"sessions_used"`
	SessionsRemaining int        `json:"sessions_remaining"`
	AmountInPaise     int64      `json:"amount_in_paise"`
	AmountInRupees    float64    `json:"amount_in_rupees"`
	ExpiryDate        *time.Time `json:"expiry_date,omitempty"`
	Status            string     `json:"status"`
	CreatedAt         time.Time  `json:"created_at"`
}

// ─── Appointments ─────────────────────────────────────────────────────────────

// CreateAppointmentRequest books a 1:1 session against a package.
// @Description Book a PT appointment. Does not consume a session credit — completing it does.
type CreateAppointmentRequest struct {
	PTPackageID     int64  `json:"pt_package_id"`    // required
	ScheduledAt     string `json:"scheduled_at"`     // required, RFC3339
	DurationMinutes int    `json:"duration_minutes"` // optional, defaults to 60
	Notes           string `json:"notes"`            // optional
}

// MarkAttendanceRequest completes, cancels, or no-shows an appointment.
// @Description Set an appointment's outcome. Only 'completed' consumes a session credit.
type MarkAttendanceRequest struct {
	Status string `json:"status"` // required: completed | cancelled | no_show
}

// AppointmentResponse is an appointment with names resolved for display.
// @Description A PT appointment.
type AppointmentResponse struct {
	ID              int64     `json:"id"`
	PTPackageID     int64     `json:"pt_package_id"`
	TrainerID       int64     `json:"trainer_id"`
	TrainerName     string    `json:"trainer_name"`
	MemberID        int64     `json:"member_id"`
	MemberName      string    `json:"member_name"`
	ScheduledAt     time.Time `json:"scheduled_at"`
	DurationMinutes int       `json:"duration_minutes"`
	Status          string    `json:"status"`
	Notes           *string   `json:"notes,omitempty"`
	CreatedAt       time.Time `json:"created_at"`
}

func paiseToRupees(p int64) float64 { return float64(p) / 100.0 }
