package lifecycle

import (
	"fmt"
	"strings"
	"time"
)

const dateLayout = "2006-01-02"

// today returns the current date truncated to midnight UTC.
// All lifecycle maths is date arithmetic, never timestamp arithmetic — a freeze
// that starts "today" must not depend on what time of day staff clicked.
func today() time.Time {
	n := time.Now().UTC()
	return time.Date(n.Year(), n.Month(), n.Day(), 0, 0, 0, 0, time.UTC)
}

// truncateDay normalises any time to midnight UTC.
func truncateDay(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
}

// daysBetween counts whole days from a to b. Negative when b precedes a.
func daysBetween(a, b time.Time) int {
	return int(truncateDay(b).Sub(truncateDay(a)).Hours() / 24)
}

// parseDateOrToday parses an optional YYYY-MM-DD string, defaulting to today.
func parseDateOrToday(s string) (time.Time, error) {
	if strings.TrimSpace(s) == "" {
		return today(), nil
	}
	t, err := time.Parse(dateLayout, strings.TrimSpace(s))
	if err != nil {
		return time.Time{}, fmt.Errorf("invalid date %q: expected YYYY-MM-DD", s)
	}
	return truncateDay(t), nil
}

// parseDateRequired parses a mandatory YYYY-MM-DD string.
func parseDateRequired(s, field string) (time.Time, error) {
	if strings.TrimSpace(s) == "" {
		return time.Time{}, fmt.Errorf("%s is required", field)
	}
	t, err := time.Parse(dateLayout, strings.TrimSpace(s))
	if err != nil {
		return time.Time{}, fmt.Errorf("invalid %s %q: expected YYYY-MM-DD", field, s)
	}
	return truncateDay(t), nil
}

// checkEffectiveDating enforces FR-01 §0.4.
//
// Backdating is allowed within a short window so staff can record something that
// happened over a weekend. Future-dating is allowed for freezes only — a
// scheduled freeze is a normal request; a scheduled termination is not, because
// it would leave the member in a state nobody can explain.
func checkEffectiveDating(d time.Time, allowFuture bool) error {
	delta := daysBetween(today(), d)

	if delta < -MaxBackdateDays {
		return ErrBackdatedTooFar
	}
	if delta > 0 {
		if !allowFuture {
			return ErrFutureDateNotAllowed
		}
		if delta > MaxFutureDateDays {
			return ErrFutureDatedTooFar
		}
	}
	return nil
}

// validateFreeze checks a freeze request in isolation — bounds that don't need
// the member's history. Allowance checks live in the service, which can read it.
func validateFreeze(req FreezeRequest) (start, end time.Time, err error) {
	start, err = parseDateOrToday(req.StartDate)
	if err != nil {
		return
	}
	end, err = parseDateRequired(req.EndDate, "end_date")
	if err != nil {
		return
	}

	if err = checkEffectiveDating(start, true); err != nil {
		return
	}

	days := daysBetween(start, end)
	switch {
	case days < MinFreezeDays:
		err = ErrFreezeTooShort
	case days > MaxFreezeDaysPerFreeze:
		err = ErrFreezeTooLong
	}

	if req.FeeInPaise < 0 {
		err = fmt.Errorf("fee cannot be negative")
	}
	return
}

func validateUnfreeze(req UnfreezeRequest) (time.Time, error) {
	d, err := parseDateOrToday(req.EffectiveDate)
	if err != nil {
		return time.Time{}, err
	}
	return d, checkEffectiveDating(d, false)
}

func validateUpgrade(req UpgradeRequest) (time.Time, error) {
	if req.NewPlanID <= 0 {
		return time.Time{}, fmt.Errorf("new_plan_id is required")
	}
	d, err := parseDateOrToday(req.EffectiveDate)
	if err != nil {
		return time.Time{}, err
	}
	return d, checkEffectiveDating(d, false)
}

func validateTransfer(req TransferRequest) (time.Time, error) {
	if req.ToMemberID <= 0 {
		return time.Time{}, fmt.Errorf("to_member_id is required")
	}
	if req.FeeInPaise < 0 {
		return time.Time{}, fmt.Errorf("fee cannot be negative")
	}
	d, err := parseDateOrToday(req.EffectiveDate)
	if err != nil {
		return time.Time{}, err
	}
	return d, checkEffectiveDating(d, false)
}

func validateTerminate(req TerminateRequest) (time.Time, error) {
	// A reason is mandatory: terminations without reasons make churn analysis
	// worthless, and churn analysis is the whole point of the retention module.
	if strings.TrimSpace(req.Reason) == "" {
		return time.Time{}, ErrReasonRequired
	}
	if req.TerminationFeePaise < 0 {
		return time.Time{}, fmt.Errorf("termination fee cannot be negative")
	}
	d, err := parseDateOrToday(req.EffectiveDate)
	if err != nil {
		return time.Time{}, err
	}
	return d, checkEffectiveDating(d, false)
}

// ptr is a small helper for the many optional fields on MembershipEvent.
func ptr[T any](v T) *T { return &v }
