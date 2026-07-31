package lifecycle

import "time"

// ─── Request DTOs ─────────────────────────────────────────────────────────────
//
// gym_id and performed_by_user_id are NEVER accepted from a payload — both come
// from the JWT. Same rule as renewals.

// FreezeRequest pauses a membership, preserving its remaining validity.
// @Description Freeze a membership. Expiry extends 1:1 with days frozen.
type FreezeRequest struct {
	StartDate  string `json:"start_date"`     // optional, YYYY-MM-DD, defaults to today
	EndDate    string `json:"end_date"`       // required, YYYY-MM-DD
	FeeInPaise int64  `json:"fee_in_paise"`   // optional, defaults to 0
	Reason     string `json:"reason"`         // optional
	Notes      string `json:"notes"`          // optional
}

// UnfreezeRequest ends a freeze, possibly early.
// @Description End a freeze. Ending early recalculates the extension to days actually used.
type UnfreezeRequest struct {
	EffectiveDate string `json:"effective_date"` // optional, YYYY-MM-DD, defaults to today
	Notes         string `json:"notes"`          // optional
}

// UpgradeRequest moves a member to a different plan mid-term.
// @Description Change a member's plan. Expiry is unchanged; the price difference is prorated.
type UpgradeRequest struct {
	NewPlanID     int64  `json:"new_plan_id"`    // required
	EffectiveDate string `json:"effective_date"` // optional, YYYY-MM-DD, defaults to today
	Reason        string `json:"reason"`         // optional
	Notes         string `json:"notes"`          // optional
}

// TransferRequest moves remaining validity to another member.
// @Description Transfer a membership. Source is terminated; target receives the plan and expiry.
type TransferRequest struct {
	ToMemberID    int64  `json:"to_member_id"`   // required
	EffectiveDate string `json:"effective_date"` // optional, YYYY-MM-DD, defaults to today
	FeeInPaise    int64  `json:"fee_in_paise"`   // optional, defaults to 0
	Reason        string `json:"reason"`         // optional
	Notes         string `json:"notes"`          // optional
}

// TerminateRequest ends a membership permanently.
// @Description Terminate a membership. Terminal — restoring requires a new membership.
type TerminateRequest struct {
	EffectiveDate       string `json:"effective_date"`          // optional, YYYY-MM-DD, defaults to today
	Reason              string `json:"reason"`                  // REQUIRED — churn analysis depends on it
	TerminationFeePaise int64  `json:"termination_fee_in_paise"` // optional, defaults to 0
	Notes               string `json:"notes"`                   // optional
}

// ─── Response DTOs ────────────────────────────────────────────────────────────

// EventResponse is one lifecycle audit record, denormalised for display so the
// Flutter client never has to resolve IDs for a timeline.
// @Description A membership lifecycle event.
type EventResponse struct {
	ID         int64     `json:"id"`
	MemberID   int64     `json:"member_id"`
	MemberName string    `json:"member_name"`
	EventType  EventType `json:"event_type"`
	// Label is a staff-readable phrase for the timeline — "Frozen for 30 days",
	// "Upgraded to Annual Pro". Built server-side so every client renders the
	// same wording.
	Label         string    `json:"label"`
	EffectiveDate time.Time `json:"effective_date"`

	OldPlanID     *int64     `json:"old_plan_id,omitempty"`
	OldPlanName   *string    `json:"old_plan_name,omitempty"`
	NewPlanID     *int64     `json:"new_plan_id,omitempty"`
	NewPlanName   *string    `json:"new_plan_name,omitempty"`
	OldExpiryDate *time.Time `json:"old_expiry_date,omitempty"`
	NewExpiryDate *time.Time `json:"new_expiry_date,omitempty"`
	OldStatus     *string    `json:"old_status,omitempty"`
	NewStatus     *string    `json:"new_status,omitempty"`

	FreezeStart *time.Time `json:"freeze_start,omitempty"`
	FreezeEnd   *time.Time `json:"freeze_end,omitempty"`
	FreezeDays  *int       `json:"freeze_days,omitempty"`

	AmountDueInPaise     int64   `json:"amount_due_in_paise"`
	AmountDueInRupees    float64 `json:"amount_due_in_rupees"`    // display only
	AmountCreditInPaise  int64   `json:"amount_credit_in_paise"`
	AmountCreditInRupees float64 `json:"amount_credit_in_rupees"` // display only
	FeeInPaise           int64   `json:"fee_in_paise"`

	RelatedMemberID   *int64  `json:"related_member_id,omitempty"`
	RelatedMemberName *string `json:"related_member_name,omitempty"`

	Reason              *string   `json:"reason,omitempty"`
	Notes               *string   `json:"notes,omitempty"`
	PerformedByUserID   int64     `json:"performed_by_user_id"`
	PerformedByUserName string    `json:"performed_by_user_name"`
	CreatedAt           time.Time `json:"created_at"`
}

// MemberLifecycleResponse is returned by every mutating operation: the member's
// resulting state plus the event that produced it. One round-trip, so the client
// can update its cached member and append to the timeline without refetching.
// @Description Result of a lifecycle operation.
type MemberLifecycleResponse struct {
	MemberID   int64  `json:"member_id"`
	MemberName string `json:"member_name"`
	Status     string `json:"status"`

	MembershipPlanID *int64     `json:"membership_plan_id,omitempty"`
	PlanName         *string    `json:"plan_name,omitempty"`
	ExpiryDate       *time.Time `json:"expiry_date,omitempty"`

	FrozenFrom        *time.Time `json:"frozen_from,omitempty"`
	FrozenUntil       *time.Time `json:"frozen_until,omitempty"`
	FreezeDaysUsedYTD int        `json:"freeze_days_used_ytd"`
	FreezeDaysLeftYTD int        `json:"freeze_days_left_ytd"`

	Event EventResponse `json:"event"`
}

// FreezeEligibilityResponse powers the freeze dialog: it tells the UI what is
// allowed *before* staff fill the form, so limits are shown rather than
// discovered through a rejected submit.
// @Description Whether a member may be frozen, and within what bounds.
type FreezeEligibilityResponse struct {
	Eligible          bool   `json:"eligible"`
	Reason            string `json:"reason,omitempty"` // populated when Eligible is false
	MinDays           int    `json:"min_days"`
	MaxDays           int    `json:"max_days"` // min(per-freeze cap, remaining annual allowance)
	FreezeDaysUsedYTD int    `json:"freeze_days_used_ytd"`
	FreezeDaysLeftYTD int    `json:"freeze_days_left_ytd"`
	CurrentlyFrozen   bool   `json:"currently_frozen"`
}

// UpgradeQuoteResponse previews the proration before staff commit to it.
// Charging a member a number they were never shown is how disputes start.
// @Description Preview of the cost of changing plan.
type UpgradeQuoteResponse struct {
	MemberID          int64   `json:"member_id"`
	CurrentPlanID     *int64  `json:"current_plan_id,omitempty"`
	CurrentPlanName   *string `json:"current_plan_name,omitempty"`
	NewPlanID         int64   `json:"new_plan_id"`
	NewPlanName       string  `json:"new_plan_name"`
	RemainingDays     int     `json:"remaining_days"`
	OldDailyRatePaise int64   `json:"old_daily_rate_paise"`
	NewDailyRatePaise int64   `json:"new_daily_rate_paise"`
	// Exactly one of these is non-zero. Positive AmountDue = member owes;
	// positive AmountCredit = a downgrade, recorded but not refunded (FR-01 §2).
	AmountDueInPaise     int64   `json:"amount_due_in_paise"`
	AmountDueInRupees    float64 `json:"amount_due_in_rupees"`
	AmountCreditInPaise  int64   `json:"amount_credit_in_paise"`
	AmountCreditInRupees float64 `json:"amount_credit_in_rupees"`
	IsDowngrade          bool    `json:"is_downgrade"`
}

// TerminationQuoteResponse previews the refund before termination is committed.
// @Description Preview of the refund owed on termination.
type TerminationQuoteResponse struct {
	MemberID             int64   `json:"member_id"`
	RemainingDays        int     `json:"remaining_days"`
	DailyRatePaise       int64   `json:"daily_rate_paise"`
	GrossRefundPaise     int64   `json:"gross_refund_in_paise"`
	TerminationFeePaise  int64   `json:"termination_fee_in_paise"`
	NetRefundPaise       int64   `json:"net_refund_in_paise"` // clamped at 0
	NetRefundInRupees    float64 `json:"net_refund_in_rupees"`
}

// paiseToRupees is display-only. Never use the result for arithmetic.
func paiseToRupees(p int64) float64 { return float64(p) / 100.0 }
