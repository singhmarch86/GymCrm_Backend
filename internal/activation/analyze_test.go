package activation

import (
	"testing"
	"time"
)

var today = time.Date(2026, 8, 9, 0, 0, 0, 0, time.UTC)

func joined(daysAgo int) time.Time { return today.AddDate(0, 0, -daysAgo) }

func visitedDaysAgo(d int) *time.Time {
	t := today.AddDate(0, 0, -d)
	return &t
}

func TestNeverStartedFiresAfterThreeDays(t *testing.T) {
	got := Evaluate(Member{ID: 1, JoinDate: joined(3), Visits: 0}, today)
	if got.State != StateNoFirstVisit {
		t.Fatalf("state = %q, want %q", got.State, StateNoFirstVisit)
	}
	if sev := got.State.Severity(); sev != "high" {
		t.Fatalf("severity = %q, want high", sev)
	}
}

func TestWeekendSignupIsNotChased(t *testing.T) {
	// Signed up two days ago with no visit yet. Somebody who joins on Saturday
	// and starts Monday is completely normal.
	got := Evaluate(Member{ID: 1, JoinDate: joined(2), Visits: 0}, today)
	if got.State != StateOnTrack {
		t.Fatalf("state = %q, want on_track — a 2-day-old signup is not a problem", got.State)
	}
}

func TestGoingQuietBeatsSlowStart(t *testing.T) {
	// This member qualifies for BOTH: 3 visits in 40 days is well under 1.5 a
	// week, and they have been silent 12 days. The more urgent one must win,
	// because a member only ever gets one row (FR-10 §3).
	got := Evaluate(Member{
		ID: 1, JoinDate: joined(40), Visits: 3, LastVisit: visitedDaysAgo(12),
	}, today)
	if got.State != StateGoingQuiet {
		t.Fatalf("state = %q, want %q", got.State, StateGoingQuiet)
	}
}

func TestNeverStartedBeatsEverything(t *testing.T) {
	got := Evaluate(Member{ID: 1, JoinDate: joined(60), Visits: 0}, today)
	if got.State != StateNoFirstVisit {
		t.Fatalf("state = %q, want %q", got.State, StateNoFirstVisit)
	}
}

func TestSlowStartFiresBelowRate(t *testing.T) {
	// 4 visits in 28 days = 1.0 a week, under the 1.5 line.
	got := Evaluate(Member{
		ID: 1, JoinDate: joined(28), Visits: 4, LastVisit: visitedDaysAgo(2),
	}, today)
	if got.State != StateSlowStart {
		t.Fatalf("state = %q, want %q (rate %.2f)", got.State, StateSlowStart, got.VisitsPerWeek)
	}
}

func TestHealthyNewMemberIsNotFlagged(t *testing.T) {
	// 12 visits in 28 days = 3 a week, coming yesterday.
	got := Evaluate(Member{
		ID: 1, JoinDate: joined(28), Visits: 12, LastVisit: visitedDaysAgo(1),
	}, today)
	if got.State != StateOnTrack {
		t.Fatalf("state = %q, want on_track", got.State)
	}
	if got.State.IsAlert() {
		t.Fatal("on_track must not raise an alert")
	}
}

func TestRateNotJudgedInTheFirstWeek(t *testing.T) {
	// One visit in 5 days is 1.4 a week — under the line, but a rate computed
	// over 5 days is meaningless and must not fire.
	got := Evaluate(Member{
		ID: 1, JoinDate: joined(5), Visits: 1, LastVisit: visitedDaysAgo(3),
	}, today)
	if got.State != StateOnTrack {
		t.Fatalf("state = %q, want on_track before day 7", got.State)
	}
}

func TestOneOrTwoVisitsThenSilenceIsSlowStartNotGoingQuiet(t *testing.T) {
	// "Went quiet" is about losing something you had. Two visits is not a
	// pattern yet, so this member is a slow start, not a lapse.
	got := Evaluate(Member{
		ID: 1, JoinDate: joined(30), Visits: 2, LastVisit: visitedDaysAgo(20),
	}, today)
	if got.State != StateSlowStart {
		t.Fatalf("state = %q, want %q", got.State, StateSlowStart)
	}
}

func TestFrozenMembersAreLeftAlone(t *testing.T) {
	// Would otherwise be a clear "never started".
	got := Evaluate(Member{
		ID: 1, JoinDate: joined(45), Visits: 0, IsFrozen: true,
	}, today)
	if got.State != StateFrozen {
		t.Fatalf("state = %q, want %q", got.State, StateFrozen)
	}
	if got.State.IsAlert() {
		t.Fatal("a frozen member must never be alerted about")
	}
}

func TestMemberLeavesProgrammeAfterNinetyDays(t *testing.T) {
	in := Evaluate(Member{ID: 1, JoinDate: joined(90), Visits: 0}, today)
	if in.State != StateNoFirstVisit {
		t.Fatalf("day 90 state = %q, want still in the programme", in.State)
	}
	out := Evaluate(Member{ID: 1, JoinDate: joined(91), Visits: 0}, today)
	if out.State != StateNotInProgramme {
		t.Fatalf("day 91 state = %q, want out of the programme", out.State)
	}
	if out.State.IsAlert() {
		t.Fatal("a member past 90 days must not raise an activation alert")
	}
}

func TestJoinDateInTheFutureIsIgnored(t *testing.T) {
	// Bad data must not produce a confident alert.
	got := Evaluate(Member{ID: 1, JoinDate: today.AddDate(0, 0, 5), Visits: 0}, today)
	if got.State != StateNotInProgramme {
		t.Fatalf("state = %q, want not in programme", got.State)
	}
}

func TestMessagesStateTheObservedFacts(t *testing.T) {
	cases := []Member{
		{ID: 1, JoinDate: joined(10), Visits: 0},
		{ID: 2, JoinDate: joined(40), Visits: 6, LastVisit: visitedDaysAgo(14)},
		{ID: 3, JoinDate: joined(28), Visits: 3, LastVisit: visitedDaysAgo(2)},
	}
	for _, m := range cases {
		a := Evaluate(m, today)
		if !a.State.IsAlert() {
			t.Fatalf("member %d: expected an alert, got %q", m.ID, a.State)
		}
		if msg := a.Message("Test Member"); msg == "" {
			t.Fatalf("member %d (%s): empty message", m.ID, a.State)
		}
	}
}
