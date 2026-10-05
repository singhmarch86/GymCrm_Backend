package rhythm

import (
	"testing"
	"time"
)

var asOf = time.Date(2026, 8, 9, 12, 0, 0, 0, istLocation)

// at builds a check-in daysAgo days before asOf, at the given local time.
func at(daysAgo, hour, minute int) time.Time {
	d := asOf.AddDate(0, 0, -daysAgo)
	return time.Date(d.Year(), d.Month(), d.Day(), hour, minute, 0, 0, istLocation)
}

// weekdayRun lays down one check-in per weekday across a range of days-ago,
// jittering the minute so the data is not artificially perfect.
func weekdayRun(fromDaysAgo, toDaysAgo, hour int, jitter []int) []time.Time {
	var out []time.Time
	i := 0
	for d := fromDaysAgo; d > toDaysAgo; d-- {
		t := asOf.AddDate(0, 0, -d)
		if t.Weekday() == time.Saturday || t.Weekday() == time.Sunday {
			continue
		}
		j := jitter[i%len(jitter)]
		i++
		out = append(out, at(d, hour, 0).Add(time.Duration(j)*time.Minute))
	}
	return out
}

func TestCircularMeanWrapsMidnight(t *testing.T) {
	// 23:40 and 00:20 must average to midnight, not to noon. Getting this
	// wrong would put every late-night member's anchor 12 hours out.
	got := circularMeanMinute([]time.Time{at(30, 23, 40), at(29, 0, 20)})
	if got != 0 {
		t.Fatalf("circular mean = %d minutes, want 0 (midnight)", got)
	}
}

func TestCircularDistanceTakesShortWayRound(t *testing.T) {
	if d := circularDistance(23*60+30, 30); d != 60 {
		t.Fatalf("23:30 to 00:30 = %d minutes, want 60", d)
	}
	if d := circularDistance(7*60, 19*60); d != 720 {
		t.Fatalf("07:00 to 19:00 = %d minutes, want 720", d)
	}
}

func TestBrokenRhythmIsFlagged(t *testing.T) {
	// The case the whole feature exists for: a 7am weekday regular who is now
	// coming at scattered times but just as often.
	var ins []time.Time
	ins = append(ins, weekdayRun(84, 28, 7, []int{0, 5, -10, 12, 3})...)
	// Recent: same cadence, all over the clock.
	scatter := []int{6, 21, 13, 18, 9, 20, 6, 14, 19, 11, 21, 7}
	i := 0
	for d := 27; d > 0; d-- {
		tt := asOf.AddDate(0, 0, -d)
		if tt.Weekday() == time.Saturday || tt.Weekday() == time.Sunday {
			continue
		}
		ins = append(ins, at(d, scatter[i%len(scatter)], 15))
		i++
	}

	p := Analyse(1, ins, asOf)
	if !p.Eligible() {
		t.Fatalf("member should be eligible: %+v", p)
	}
	if !p.IsBroken {
		t.Fatalf("broken rhythm not flagged: anchor=%d baseline=%.2f recent=%.2f rates %.2f->%.2f",
			p.AnchorMinute, p.BaselineConsistency, p.RecentConsistency, p.BaselineRate, p.RecentRate)
	}
	if p.AnchorMinute < 6*60 || p.AnchorMinute > 8*60 {
		t.Fatalf("anchor = %d, want near 07:00", p.AnchorMinute)
	}
	if p.Severity != "high" && p.Severity != "medium" {
		t.Fatalf("severity = %q, want high or medium for a full slot loss", p.Severity)
	}
}

func TestSteadyRhythmIsNotFlagged(t *testing.T) {
	var ins []time.Time
	ins = append(ins, weekdayRun(84, 28, 7, []int{0, 5, -10, 12, 3})...)
	ins = append(ins, weekdayRun(27, 0, 7, []int{2, -6, 8, 0, 11})...)

	p := Analyse(1, ins, asOf)
	if !p.Eligible() {
		t.Fatalf("member should be eligible: %+v", p)
	}
	if p.IsBroken {
		t.Fatalf("steady member flagged: recent consistency %.2f", p.RecentConsistency)
	}
	if !p.Recovered() {
		t.Fatalf("steady member should count as recovered, consistency %.2f", p.RecentConsistency)
	}
}

func TestCollapsedAttendanceIsLeftToInactivityAlerts(t *testing.T) {
	// A member who has nearly stopped coming is owned by inactive_1_week /
	// inactive_2_weeks. Firing here too would double-list them in At Risk.
	var ins []time.Time
	ins = append(ins, weekdayRun(84, 28, 7, []int{0, 5, -10, 12, 3})...)
	// Four visits in four weeks, at random times — a big consistency drop, but
	// the rate has collapsed to well under 60% of baseline.
	ins = append(ins, at(24, 19, 0), at(17, 13, 30), at(9, 21, 15), at(3, 6, 45))

	p := Analyse(1, ins, asOf)
	if !p.Eligible() {
		t.Fatalf("member should still be eligible: %+v", p)
	}
	if p.IsBroken {
		t.Fatalf("collapsed-attendance member flagged by rhythm break; rates %.2f -> %.2f",
			p.BaselineRate, p.RecentRate)
	}
}

func TestFreeFloaterNeverEligible(t *testing.T) {
	// Someone who always came at random times has no rhythm to break.
	var ins []time.Time
	hours := []int{6, 20, 11, 17, 8, 21, 13, 7, 19, 10, 22, 15, 9, 18, 12, 6, 20, 16}
	for i, h := range hours {
		ins = append(ins, at(80-3*i, h, 10))
	}
	for i, h := range hours[:10] {
		ins = append(ins, at(26-2*i, h, 40))
	}

	p := Analyse(1, ins, asOf)
	if p.Eligible() {
		t.Fatalf("free-floater judged eligible, baseline consistency %.2f", p.BaselineConsistency)
	}
	if p.IsBroken {
		t.Fatal("free-floater flagged as broken")
	}
}

func TestSparseBaselineNeverEligible(t *testing.T) {
	// Perfectly consistent, but only six visits — not enough to call a rhythm.
	var ins []time.Time
	for d := 80; d > 28; d -= 9 {
		ins = append(ins, at(d, 7, 0))
	}
	for d := 24; d > 0; d -= 5 {
		ins = append(ins, at(d, 19, 0))
	}

	p := Analyse(1, ins, asOf)
	if p.Eligible() {
		t.Fatalf("sparse member judged eligible, %d baseline visits", p.BaselineVisits)
	}
}

func TestCrammedBaselineNeverEligible(t *testing.T) {
	// Twelve visits, all inside one week, all at 07:00. Visit count and
	// consistency both pass; the distinct-weeks gate is what must catch this.
	var ins []time.Time
	for i := 0; i < 12; i++ {
		ins = append(ins, at(34-i/2, 7, 0).Add(time.Duration(i%2)*time.Hour/6))
	}
	for d := 26; d > 0; d -= 3 {
		ins = append(ins, at(d, 20, 0))
	}

	p := Analyse(1, ins, asOf)
	if p.BaselineWeeks >= minBaselineWeeks {
		t.Fatalf("test setup wrong: baseline spans %d weeks", p.BaselineWeeks)
	}
	if p.Eligible() {
		t.Fatal("member with a one-week baseline judged eligible")
	}
}

func TestTimestampsAreReadInIST(t *testing.T) {
	// A 07:00 IST check-in stored as UTC must read as hour 7, not 1:30. If this
	// regresses, every anchor in the system shifts by five and a half hours.
	utc := time.Date(2026, 7, 1, 1, 30, 0, 0, time.UTC)
	p := Analyse(1, []time.Time{utc}, asOf)
	if p.AnchorMinute != 7*60 {
		t.Fatalf("anchor = %d minutes, want 420 (07:00 IST)", p.AnchorMinute)
	}
}

func TestWindowsDoNotOverlap(t *testing.T) {
	// A visit exactly 28 days ago belongs to the recent window, and one 29 days
	// ago to the baseline — no timestamp may be counted twice.
	p := Analyse(1, []time.Time{at(28, 7, 0), at(29, 7, 0), at(85, 7, 0)}, asOf)
	if p.RecentVisits != 1 {
		t.Fatalf("recent visits = %d, want 1", p.RecentVisits)
	}
	if p.BaselineVisits != 1 {
		t.Fatalf("baseline visits = %d, want 1 (the 85-day-old visit is out of range)", p.BaselineVisits)
	}
}

func TestFormatMinute(t *testing.T) {
	cases := map[int]string{0: "12:00am", 420: "7:00am", 720: "12:00pm", 1155: "7:15pm", 1439: "11:59pm"}
	for m, want := range cases {
		if got := formatMinute(m); got != want {
			t.Fatalf("formatMinute(%d) = %q, want %q", m, got, want)
		}
	}
}
