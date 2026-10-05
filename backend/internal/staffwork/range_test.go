package staffwork

import (
	"errors"
	"testing"
	"time"
)

func TestBareDateIsAOneDayRange(t *testing.T) {
	r, err := ParseRange("2026-08-11", "", "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !r.IsSingleDay() || r.Days() != 1 {
		t.Fatalf("days = %d, want 1", r.Days())
	}
	if r.FromString() != "2026-08-11" || r.ToString() != "2026-08-11" {
		t.Fatalf("got %s..%s", r.FromString(), r.ToString())
	}
}

func TestNoParametersMeansTodayInIST(t *testing.T) {
	r, err := ParseRange("", "", "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := time.Now().In(IST).Format("2006-01-02")
	if r.FromString() != want || !r.IsSingleDay() {
		t.Fatalf("got %s, want single day %s", r.Label(), want)
	}
}

// Inclusive at both ends: an owner asking for the 1st to the 31st means the
// 31st is in it.
func TestRangeIsInclusiveAtBothEnds(t *testing.T) {
	r, err := ParseRange("", "2026-08-01", "2026-08-31")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if r.Days() != 31 {
		t.Fatalf("August has 31 days, got %d", r.Days())
	}
	if r.IsSingleDay() {
		t.Fatal("a month is not a single day")
	}
}

func TestSameFromAndToIsOneDayNotZero(t *testing.T) {
	r, _ := ParseRange("", "2026-08-11", "2026-08-11")
	if r.Days() != 1 {
		t.Fatalf("days = %d, want 1", r.Days())
	}
}

// A lone from would otherwise get silently completed to today, answering a
// question nobody asked.
func TestHalfARangeIsRejected(t *testing.T) {
	if _, err := ParseRange("", "2026-08-01", ""); !errors.Is(err, ErrBadRange) {
		t.Fatalf("lone from: err = %v, want ErrBadRange", err)
	}
	if _, err := ParseRange("", "", "2026-08-31"); !errors.Is(err, ErrBadRange) {
		t.Fatalf("lone to: err = %v, want ErrBadRange", err)
	}
}

func TestBackwardsRangeIsRejected(t *testing.T) {
	_, err := ParseRange("", "2026-08-31", "2026-08-01")
	if !errors.Is(err, ErrRangeBack) {
		t.Fatalf("err = %v, want ErrRangeBack", err)
	}
}

// A mistyped year would drag every row the gym has ever written through the
// eight-ledger union.
func TestAbsurdlyLongRangeIsRejected(t *testing.T) {
	_, err := ParseRange("", "2000-01-01", "2026-08-11")
	if !errors.Is(err, ErrRangeHuge) {
		t.Fatalf("err = %v, want ErrRangeHuge", err)
	}
}

func TestExactlyMaxRangeIsAccepted(t *testing.T) {
	from := time.Date(2026, 1, 1, 0, 0, 0, 0, IST)
	to := from.AddDate(0, 0, MaxRangeDays-1)
	r, err := ParseRange("", from.Format("2006-01-02"), to.Format("2006-01-02"))
	if err != nil {
		t.Fatalf("the boundary itself should be allowed: %v", err)
	}
	if r.Days() != MaxRangeDays {
		t.Fatalf("days = %d, want %d", r.Days(), MaxRangeDays)
	}
}

func TestGarbageRangeIsRejected(t *testing.T) {
	for _, pair := range [][2]string{
		{"01-08-2026", "31-08-2026"},
		{"2026-08-01", "yesterday"},
		{"2026-13-45", "2026-13-46"},
		{"'; DROP TABLE payments; --", "2026-08-01"},
	} {
		if _, err := ParseRange("", pair[0], pair[1]); err == nil {
			t.Fatalf("ParseRange(%q, %q) should have failed", pair[0], pair[1])
		}
	}
}

func TestRangeEndsUseISTNotServerTime(t *testing.T) {
	r, err := ParseRange("", "2026-08-01", "2026-08-31")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	for _, end := range []time.Time{r.From, r.To} {
		if _, offset := end.Zone(); offset != 5*3600+30*60 {
			t.Fatalf("offset = %d, want IST (19800)", offset)
		}
	}
}

// A month spanning a DST-style clock change must still count calendar days.
// IST has no DST, but Days() must not be doing wall-clock arithmetic that
// would break if the zone ever changed underneath it.
func TestDaysCountsCalendarDaysNotHours(t *testing.T) {
	r, _ := ParseRange("", "2026-02-01", "2026-03-01")
	if r.Days() != 29 {
		t.Fatalf("1 Feb to 1 Mar 2026 inclusive is 29 days, got %d", r.Days())
	}
}
