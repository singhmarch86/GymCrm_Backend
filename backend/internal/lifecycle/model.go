package lifecycle

import "time"

// EventType enumerates the membership state transitions this module records.
// Mirrors chk_membership_events_type in migration 012.
type EventType string

const (
	EventFreeze      EventType = "freeze"
	EventUnfreeze    EventType = "unfreeze"
	EventUpgrade     EventType = "upgrade"
	EventTransferOut EventType = "transfer_out"
	EventTransferIn  EventType = "transfer_in"
	EventTerminate   EventType = "terminate"
)

// Member statuses this module reads and writes.
// 'active' and 'expired' predate this module; 'frozen' and 'terminated' are new.
const (
	StatusActive     = "active"
	StatusExpired    = "expired"
	StatusFrozen     = "frozen"
	StatusTerminated = "terminated"
)

// Policy constants — see docs/FR-01-membership-lifecycle.md.
// These are deliberately named and gathered here so they can be changed without
// hunting through logic. Every one of them is a business decision, not a
// technical constraint.
const (
	MinFreezeDays          = 7  // FR-01 §1
	MaxFreezeDaysPerFreeze = 90 // FR-01 §1
	MaxFreezeDaysPerYear   = 90 // FR-01 §1
	MaxBackdateDays        = 7  // FR-01 §0.4
	MaxFutureDateDays      = 30 // FR-01 §0.4 — freeze only
)

// MembershipEvent is an immutable audit record of one lifecycle operation.
// Insert-only: never updated, never deleted, never soft-deleted. Same contract
// as renewals.Renewal.
//
// A transfer writes TWO rows — transfer_out on the source member and
// transfer_in on the target — each carrying RelatedMemberID pointing at the
// other, so a resold membership can always be traced end to end.
//
// Money fields are paise (int64), matching renewals.AmountPaidInPaise:
//   - AmountDueInPaise:    positive = member owes (upgrade delta, fees)
//   - AmountCreditInPaise: positive = member is owed (downgrade credit, refund)
//
// Neither is collected or disbursed here. Lifecycle records what is owed;
// the payments module moves money. See FR-01 §5.
type MembershipEvent struct {
	ID       int64 `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID    int64 `gorm:"not null"                 json:"gym_id"`
	MemberID int64 `gorm:"not null"                 json:"member_id"`

	EventType     EventType `gorm:"type:varchar(20);not null" json:"event_type"`
	EffectiveDate time.Time `gorm:"type:date;not null"        json:"effective_date"`

	// State either side of the operation. Nullable because not every event type
	// touches every field — a freeze does not change the plan.
	OldPlanID     *int64     `json:"old_plan_id,omitempty"`
	NewPlanID     *int64     `json:"new_plan_id,omitempty"`
	OldExpiryDate *time.Time `gorm:"type:date" json:"old_expiry_date,omitempty"`
	NewExpiryDate *time.Time `gorm:"type:date" json:"new_expiry_date,omitempty"`
	OldStatus     *string    `gorm:"type:varchar(20)" json:"old_status,omitempty"`
	NewStatus     *string    `gorm:"type:varchar(20)" json:"new_status,omitempty"`

	// Freeze-specific
	FreezeStart *time.Time `gorm:"type:date" json:"freeze_start,omitempty"`
	FreezeEnd   *time.Time `gorm:"type:date" json:"freeze_end,omitempty"`
	FreezeDays  *int       `json:"freeze_days,omitempty"`

	AmountDueInPaise    int64 `gorm:"not null;default:0" json:"amount_due_in_paise"`
	AmountCreditInPaise int64 `gorm:"not null;default:0" json:"amount_credit_in_paise"`
	FeeInPaise          int64 `gorm:"not null;default:0" json:"fee_in_paise"`

	RelatedMemberID *int64 `json:"related_member_id,omitempty"`

	Reason            *string   `gorm:"type:text" json:"reason,omitempty"`
	Notes             *string   `gorm:"type:text" json:"notes,omitempty"`
	PerformedByUserID int64     `gorm:"not null"  json:"performed_by_user_id"`
	CreatedAt         time.Time `gorm:"autoCreateTime" json:"created_at"`
}

func (MembershipEvent) TableName() string { return "membership_events" }

// memberSnapshot is the subset of the members row this module reads and writes.
// Deliberately not the full members.Member — lifecycle has no business touching
// contact details, and a narrow struct makes that impossible by construction.
type memberSnapshot struct {
	ID                int64
	GymID             int64
	FirstName         string
	LastName          string
	Status            string
	MembershipPlanID  *int64
	StartDate         *time.Time
	ExpiryDate        *time.Time
	JoinDate          time.Time
	FrozenFrom        *time.Time
	FrozenUntil       *time.Time
	FreezeDaysUsedYTD int
	FreezeYearStart   *time.Time
}

// planSnapshot is the subset of membership_plans needed for proration maths.
type planSnapshot struct {
	ID           int64
	Name         string
	PriceInPaise int64
	DurationDays int
	IsActive     bool
}

// dailyRatePaise is the per-day value of a plan, used for proration on upgrade
// and refund on termination.
//
// Integer division truncates: the member gains at most 1 paise/day on charges
// and loses at most 1 paise/day on refunds. Accepted deliberately — the
// alternative is carrying fractional paise, which no accounting system wants.
// See FR-01 §0.2.
func (p planSnapshot) dailyRatePaise() int64 {
	if p.DurationDays <= 0 {
		return 0
	}
	return p.PriceInPaise / int64(p.DurationDays)
}

// isEffectivelyFrozen reports whether the member is frozen *right now*.
//
// A member whose frozen_until has passed is active again even though nothing
// has written to the row yet — auto-thaw is computed on read rather than by a
// scheduled job, so it stays correct even if no background worker is running.
// See FR-01 §1 (Auto-thaw).
func (m memberSnapshot) isEffectivelyFrozen(today time.Time) bool {
	if m.Status != StatusFrozen || m.FrozenUntil == nil {
		return false
	}
	return !today.After(*m.FrozenUntil)
}

// remainingDays counts membership days left from the given date, floored at 0.
func (m memberSnapshot) remainingDays(from time.Time) int {
	if m.ExpiryDate == nil {
		return 0
	}
	d := int(m.ExpiryDate.Sub(from).Hours() / 24)
	if d < 0 {
		return 0
	}
	return d
}

func (m memberSnapshot) fullName() string { return m.FirstName + " " + m.LastName }
