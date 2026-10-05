package staffwork

import (
	"errors"
	"fmt"
	"time"
)

// Date ranges for staff work (FR-18 §9).
//
// This supersedes FR-13 §4, which said one day at a time and left ranges as an
// open question. "What did Simran do in July" is a fair question and a
// single-day screen cannot answer it.
//
// What does not change is FR-13 §1: no score, no ranking, ordered by name. A
// month of aggregates reads far more like a performance review than a day
// does, so the anti-leaderboard rules matter more here, not less.

var (
	ErrBadRange  = errors.New("staffwork: from and to must both be YYYY-MM-DD")
	ErrRangeBack = errors.New("staffwork: to is before from")
	ErrRangeHuge = errors.New("staffwork: range is longer than a year")
)

// MaxRangeDays caps a request at roughly a year.
//
// Not a performance guess — the union scans eight ledgers, and an accidental
// year-2000 "from" would drag every row the gym has ever written through one
// request. A year is longer than any question this screen is meant to answer.
const MaxRangeDays = 366

// Range is an inclusive span of gym-local days. Both ends use the IST day
// boundary, the same one a single day uses.
type Range struct {
	From time.Time
	To   time.Time
}

// SingleDay is the range a bare ?date= produces.
func SingleDay(d time.Time) Range { return Range{From: d, To: d} }

func (r Range) FromString() string { return r.From.Format("2006-01-02") }
func (r Range) ToString() string   { return r.To.Format("2006-01-02") }

// Days is the inclusive length: one day is 1, not 0.
func (r Range) Days() int {
	a := time.Date(r.From.Year(), r.From.Month(), r.From.Day(), 0, 0, 0, 0, IST)
	b := time.Date(r.To.Year(), r.To.Month(), r.To.Day(), 0, 0, 0, 0, IST)
	return int(b.Sub(a).Hours()/24) + 1
}

func (r Range) IsSingleDay() bool { return r.Days() == 1 }

// ParseRange reads the query parameters, accepting both the old and new forms.
//
//	?date=YYYY-MM-DD          one day (what the screen sent before §9)
//	?from=…&to=…              an inclusive span
//	(nothing)                 today, in the gym's timezone
//
// from and to must be given together. Accepting a lone "from" and silently
// running it to today would answer a question nobody asked, and the caller
// would have no way to tell.
func ParseRange(date, from, to string) (Range, error) {
	if from == "" && to == "" {
		d, err := ParseDay(date)
		if err != nil {
			return Range{}, err
		}
		return SingleDay(d), nil
	}
	if from == "" || to == "" {
		return Range{}, ErrBadRange
	}

	f, err := time.ParseInLocation("2006-01-02", from, IST)
	if err != nil {
		return Range{}, ErrBadRange
	}
	t, err := time.ParseInLocation("2006-01-02", to, IST)
	if err != nil {
		return Range{}, ErrBadRange
	}

	rng := Range{From: f, To: t}
	if t.Before(f) {
		return Range{}, ErrRangeBack
	}
	if rng.Days() > MaxRangeDays {
		return Range{}, ErrRangeHuge
	}
	return rng, nil
}

// Label is how the range should read on screen when the client has no better
// idea of its own — used in logs and in the API's echo of what it answered.
func (r Range) Label() string {
	if r.IsSingleDay() {
		return r.FromString()
	}
	return fmt.Sprintf("%s to %s", r.FromString(), r.ToString())
}
