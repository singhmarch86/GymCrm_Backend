package activation

import (
	"fmt"
	"time"
)

// Pure evaluation of a member's first 90 days. No database, no HTTP — just the
// rules from docs/FR-10, so each one can be tested exactly.

// Tunables. Every one is a decision the gym owner should be able to argue
// with (FR-10 §8), so they live together rather than scattered through the
// query.
const (
	// How long a member is watched. Chosen to hand over cleanly to
	// rhythm-break detection, which needs ~3 months of history before it can
	// say anything — the two are adjacent with no gap.
	programmeDays = 90

	// Long enough that somebody who signs up on Saturday and starts Monday
	// isn't chased.
	neverStartedAfterDays = 3

	// A visit rate computed over three days is meaningless.
	slowStartAfterDays = 7

	// Roughly twice a week is where a behaviour turns automatic; this sits
	// just below so one slow week doesn't trigger a call. NOT derived from
	// real member data — see FR-10 §8.
	minVisitsPerWeek = 1.5

	// Ten rather than seven: a new member's pattern is naturally erratic and a
	// week off is common. Ten is where it stops being noise.
	goingQuietAfterDays = 10
	goingQuietMinVisits = 3
)

// State is what the programme thinks of one member right now.
type State string

const (
	// StateNotInProgramme — joined more than 90 days ago, or not active.
	StateNotInProgramme State = ""
	// StateFrozen — in the window but frozen; deliberately left alone.
	StateFrozen State = "frozen"
	// StateOnTrack — in the window and doing fine. No alert.
	StateOnTrack State = "on_track"

	StateNoFirstVisit State = "activation_no_first_visit"
	StateSlowStart    State = "activation_slow_start"
	StateGoingQuiet   State = "activation_going_quiet"
)

// IsAlert reports whether this state should raise a row in the alert queue.
func (s State) IsAlert() bool {
	return s == StateNoFirstVisit || s == StateSlowStart || s == StateGoingQuiet
}

// Severity drives the colour in the At Risk list.
func (s State) Severity() string {
	switch s {
	case StateNoFirstVisit, StateGoingQuiet:
		return "high"
	case StateSlowStart:
		return "medium"
	default:
		return "low"
	}
}

// Member is everything needed to judge one member's activation.
type Member struct {
	ID        int64
	Name      string
	JoinDate  time.Time
	Visits    int
	LastVisit *time.Time // nil when they have never checked in
	IsFrozen  bool
}

// Assessment is the verdict plus the numbers that justify it, so the screen
// can show why rather than asking anyone to trust a label.
type Assessment struct {
	MemberID           int64
	State              State
	DaysSinceJoin      int
	Visits             int
	DaysSinceLastVisit int // -1 when they have never visited
	VisitsPerWeek      float64
}

// Evaluate applies the FR-10 rules to one member as of the given day.
func Evaluate(m Member, today time.Time) Assessment {
	days := daysBetween(m.JoinDate, today)

	a := Assessment{
		MemberID:           m.ID,
		DaysSinceJoin:      days,
		Visits:             m.Visits,
		DaysSinceLastVisit: -1,
	}
	if m.LastVisit != nil {
		a.DaysSinceLastVisit = daysBetween(*m.LastVisit, today)
	}
	if days > 0 {
		a.VisitsPerWeek = float64(m.Visits) / (float64(days) / 7.0)
	}

	// Joined in the future, or too long ago: not our business.
	if days < 0 || days > programmeDays {
		a.State = StateNotInProgramme
		return a
	}
	// A member who froze for a medical reason has not failed to activate, and
	// calling them about it would be insulting (FR-10 §1).
	if m.IsFrozen {
		a.State = StateFrozen
		return a
	}

	// Priority order matters: the more urgent problem wins the single row this
	// member is allowed (FR-10 §3).

	// 1. Paid and never walked in. The highest-leverage call in the product.
	if m.Visits == 0 {
		if days >= neverStartedAfterDays {
			a.State = StateNoFirstVisit
		} else {
			// Still within the grace period — nothing has gone wrong yet.
			a.State = StateOnTrack
		}
		return a
	}

	// 2. Had it, lost it. For a new member a ten-day gap is usually the end.
	if m.Visits >= goingQuietMinVisits && a.DaysSinceLastVisit >= goingQuietAfterDays {
		a.State = StateGoingQuiet
		return a
	}

	// 3. Coming, but never often enough to become a habit.
	if days >= slowStartAfterDays && a.VisitsPerWeek < minVisitsPerWeek {
		a.State = StateSlowStart
		return a
	}

	a.State = StateOnTrack
	return a
}

// Message is the line staff read in the At Risk queue. It states what was
// observed and what the call is for — no invented score (FR-10 §6).
func (a Assessment) Message(name string) string {
	switch a.State {
	case StateNoFirstVisit:
		return fmt.Sprintf(
			"%s joined %d days ago and has not checked in once. They have paid and "+
				"never walked through the door — this is the easiest member on the list to save, "+
				"and it gets harder every day.",
			name, a.DaysSinceJoin)

	case StateGoingQuiet:
		return fmt.Sprintf(
			"%s came %d times after joining %d days ago, then stopped — %d days ago now. "+
				"They started building something and lost it. A new member rarely comes back on their own.",
			name, a.Visits, a.DaysSinceJoin, a.DaysSinceLastVisit)

	case StateSlowStart:
		return fmt.Sprintf(
			"%s has come %d times in %d days — about %.1f visits a week. That is not often "+
				"enough to become a habit, and habits are what make members renew. Worth asking what "+
				"would make it easier for them to get here.",
			name, a.Visits, a.DaysSinceJoin, a.VisitsPerWeek)
	}
	return ""
}

// daysBetween counts whole days from a to b, ignoring time of day.
func daysBetween(a, b time.Time) int {
	da := time.Date(a.Year(), a.Month(), a.Day(), 0, 0, 0, 0, time.UTC)
	db := time.Date(b.Year(), b.Month(), b.Day(), 0, 0, 0, 0, time.UTC)
	return int(db.Sub(da).Hours() / 24)
}
