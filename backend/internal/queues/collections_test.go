package queues

import (
	"testing"
	"time"
)

// The grouping rules are the whole feature, so they are pinned here directly
// rather than only through the database.
//
// classify mirrors the branch order in Service.Collections. If that order
// changes and this does not, one of the two is wrong — which is the point.
func classify(
	daysOverdue *int, lastActivityType *string, promisedOn *time.Time,
	lastContactAt *time.Time, today time.Time,
) string {
	if lastActivityType != nil && *lastActivityType == ActivityPromise &&
		promisedOn != nil && !promisedOn.Before(today) {
		return GroupPromised
	}
	if daysOverdue != nil && *daysOverdue < 0 {
		return GroupUpcoming
	}
	if lastContactAt == nil {
		return GroupUnchased
	}
	return GroupChased
}

func day(y int, m time.Month, d int) time.Time {
	return time.Date(y, m, d, 0, 0, 0, 0, IST)
}

func ptrInt(v int) *int       { return &v }
func ptrStr(v string) *string { return &v }

func TestUntouchedOverdueGoesToUnchased(t *testing.T) {
	today := day(2026, time.August, 12)
	got := classify(ptrInt(30), nil, nil, nil, today)
	if got != GroupUnchased {
		t.Fatalf("got %s, want %s", got, GroupUnchased)
	}
}

func TestContactedOverdueGoesToChased(t *testing.T) {
	today := day(2026, time.August, 12)
	contacted := day(2026, time.August, 10)
	got := classify(ptrInt(30), ptrStr(ActivityContact), nil, &contacted, today)
	if got != GroupChased {
		t.Fatalf("got %s, want %s", got, GroupChased)
	}
}

// A call that rang out still counts as chased. Somebody did try, and leaving
// it under "nobody has chased these" would send the next person to repeat the
// same call.
func TestUnreachedContactStillCountsAsChased(t *testing.T) {
	today := day(2026, time.August, 12)
	contacted := day(2026, time.August, 11)
	got := classify(ptrInt(5), ptrStr(ActivityContact), nil, &contacted, today)
	if got != GroupChased {
		t.Fatalf("got %s, want %s", got, GroupChased)
	}
}

func TestLivePromiseGoesToPromised(t *testing.T) {
	today := day(2026, time.August, 12)
	contacted := day(2026, time.August, 10)
	promise := day(2026, time.August, 20)
	got := classify(ptrInt(30), ptrStr(ActivityPromise), &promise, &contacted, today)
	if got != GroupPromised {
		t.Fatalf("got %s, want %s", got, GroupPromised)
	}
}

// A promise due today has not been broken yet — the day is not over.
func TestPromiseDueTodayIsStillLive(t *testing.T) {
	today := day(2026, time.August, 12)
	contacted := day(2026, time.August, 1)
	promise := day(2026, time.August, 12)
	got := classify(ptrInt(30), ptrStr(ActivityPromise), &promise, &contacted, today)
	if got != GroupPromised {
		t.Fatalf("a promise due today is live, got %s", got)
	}
}

// Once the date passes without payment the promise was not kept. Leaving it
// under Promised would quietly hide a broken commitment.
func TestBrokenPromiseFallsBackToChased(t *testing.T) {
	today := day(2026, time.August, 12)
	contacted := day(2026, time.August, 1)
	promise := day(2026, time.August, 5)
	got := classify(ptrInt(40), ptrStr(ActivityPromise), &promise, &contacted, today)
	if got != GroupChased {
		t.Fatalf("got %s, want %s", got, GroupChased)
	}
}

// Chasing something that is not due yet is not diligence, so an untouched
// future due must not be called unchased.
func TestFutureDueIsUpcomingNotUnchased(t *testing.T) {
	today := day(2026, time.August, 12)
	got := classify(ptrInt(-5), nil, nil, nil, today)
	if got != GroupUpcoming {
		t.Fatalf("got %s, want %s", got, GroupUpcoming)
	}
}

// A promise on a not-yet-due payment still shows as promised: the member has
// told the gym something, and that is the more useful state.
func TestPromiseBeatsUpcoming(t *testing.T) {
	today := day(2026, time.August, 12)
	promise := day(2026, time.August, 30)
	contacted := day(2026, time.August, 11)
	got := classify(ptrInt(-5), ptrStr(ActivityPromise), &promise, &contacted, today)
	if got != GroupPromised {
		t.Fatalf("got %s, want %s", got, GroupPromised)
	}
}

// A due with no date at all is a data problem, not the most urgent debt in the
// gym. It must not be treated as due in the far future either.
func TestDueWithNoDateIsUnchasedNotUpcoming(t *testing.T) {
	today := day(2026, time.August, 12)
	got := classify(nil, nil, nil, nil, today)
	if got != GroupUnchased {
		t.Fatalf("got %s, want %s", got, GroupUnchased)
	}
}

func TestDueTodayIsChaseableNotUpcoming(t *testing.T) {
	today := day(2026, time.August, 12)
	got := classify(ptrInt(0), nil, nil, nil, today)
	if got != GroupUnchased {
		t.Fatalf("0 days overdue is due now, got %s", got)
	}
}
