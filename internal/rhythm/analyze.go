package rhythm

import (
	"fmt"
	"math"
	"time"
)

// Pure analysis. No database, no HTTP — everything here is arithmetic on
// check-in timestamps, so it can be tested exactly. See docs/FR-09.

// India observes no daylight saving, so a fixed offset is not an approximation
// here — it is exactly correct, and it avoids depending on tzdata being present
// in the container image.
var istLocation = time.FixedZone("IST", 5*60*60+30*60)

// Tunables. Every one of these is a POLICY question in FR-09 §8, deliberately
// gathered in one place so changing the gym's mind is a one-line edit.
const (
	// How far from the anchor a check-in can land and still count as "kept the
	// slot". The single most important number in the feature (FR-09 §8).
	slotToleranceMinutes = 90

	baselineDays = 84 // 12 weeks ago .. 4 weeks ago
	recentDays   = 28 // 4 weeks ago .. today

	// Eligibility: you cannot break a rhythm you never had (FR-09 §2).
	minBaselineVisits      = 12
	minBaselineWeeks       = 6
	minBaselineConsistency = 0.70
	minRecentVisits        = 4

	// Firing rules (FR-09 §3).
	maxRecentConsistency = 0.40
	minConsistencyDrop   = 0.30
	minRateRetention     = 0.60

	// Recovery is above the firing threshold so a member hovering at the line
	// does not flap open/closed on every scan (FR-09 §5).
	recoveryConsistency = 0.60

	severityHighDrop   = 0.55
	severityMediumDrop = 0.42
)

// Profile is what the analysis produces for one member. It is a description of
// how they train; IsBroken is only one field of it.
type Profile struct {
	MemberID int64

	AnchorMinute int // minutes past local midnight

	BaselineVisits      int
	BaselineWeeks       int
	BaselineOnSlot      int
	BaselineConsistency float64
	BaselineRate        float64 // visits per week
	BaselineWeekdays    string

	RecentVisits      int
	RecentOnSlot      int
	RecentConsistency float64
	RecentRate        float64
	RecentWeekdays    string

	IsBroken bool
	Severity string
}

// Eligible reports whether this member had an established rhythm to break at
// all. Ineligible members are never flagged by this feature (FR-09 §2).
func (p *Profile) Eligible() bool {
	return p.BaselineVisits >= minBaselineVisits &&
		p.BaselineWeeks >= minBaselineWeeks &&
		p.BaselineConsistency >= minBaselineConsistency &&
		p.RecentVisits >= minRecentVisits
}

// Recovered reports whether an already-open alert should auto-resolve.
func (p *Profile) Recovered() bool {
	return p.RecentVisits >= minRecentVisits && p.RecentConsistency >= recoveryConsistency
}

// Analyse computes a member's rhythm from raw check-in timestamps. asOf is the
// date the scan is evaluating against; timestamps outside the two windows are
// ignored, so the caller may pass a slightly wider query result.
func Analyse(memberID int64, checkIns []time.Time, asOf time.Time) *Profile {
	asOf = asOf.In(istLocation)
	// Window edges sit on local midnight, not on the moment the scan happens.
	// Otherwise a member's window boundary moves with the time of day the owner
	// clicked Scan, and the same data yields different answers before and after
	// lunch.
	dayStart := time.Date(asOf.Year(), asOf.Month(), asOf.Day(), 0, 0, 0, 0, istLocation)
	recentStart := dayStart.AddDate(0, 0, -recentDays)
	baselineStart := dayStart.AddDate(0, 0, -baselineDays)

	var baseline, recent []time.Time
	for _, t := range checkIns {
		local := t.In(istLocation)
		switch {
		case !local.Before(recentStart) && !local.After(asOf):
			recent = append(recent, local)
		case !local.Before(baselineStart) && local.Before(recentStart):
			baseline = append(baseline, local)
		}
	}

	p := &Profile{
		MemberID:         memberID,
		BaselineVisits:   len(baseline),
		RecentVisits:     len(recent),
		BaselineWeeks:    distinctWeeks(baseline),
		BaselineWeekdays: weekdayBitmap(baseline),
		RecentWeekdays:   weekdayBitmap(recent),
		BaselineRate:     float64(len(baseline)) / (float64(baselineDays-recentDays) / 7.0),
		RecentRate:       float64(len(recent)) / (float64(recentDays) / 7.0),
	}

	if len(baseline) == 0 {
		return p
	}

	p.AnchorMinute = circularMeanMinute(baseline)
	p.BaselineOnSlot = countOnSlot(baseline, p.AnchorMinute)
	p.BaselineConsistency = float64(p.BaselineOnSlot) / float64(len(baseline))

	if len(recent) > 0 {
		// Measured against the *baseline* anchor, not a recomputed one: the
		// question is whether they still keep their old slot (FR-09 §1.3).
		p.RecentOnSlot = countOnSlot(recent, p.AnchorMinute)
		p.RecentConsistency = float64(p.RecentOnSlot) / float64(len(recent))
	}

	if !p.Eligible() {
		return p
	}

	drop := p.BaselineConsistency - p.RecentConsistency
	// The rate rule is what keeps this feature out of the inactivity alerts'
	// territory: if attendance has already collapsed, those alerts own the
	// member and this one stays silent (FR-09 §3).
	rateHeld := p.RecentRate >= minRateRetention*p.BaselineRate

	if p.RecentConsistency <= maxRecentConsistency && drop >= minConsistencyDrop && rateHeld {
		p.IsBroken = true
		switch {
		case drop >= severityHighDrop:
			p.Severity = "high"
		case drop >= severityMediumDrop:
			p.Severity = "medium"
		default:
			p.Severity = "low"
		}
	}
	return p
}

// Message is the line a staff member reads in the At Risk queue. It states the
// observed facts and nothing else — no invented risk score (FR-09 §6).
func (p *Profile) Message(memberName string) string {
	return fmt.Sprintf(
		"%s used to train around %s — %d of %d visits were in that slot. "+
			"In the last 4 weeks only %d of %d were, but they are still coming %.1f times a week (was %.1f). "+
			"The habit has broken before the attendance has.",
		memberName, formatMinute(p.AnchorMinute),
		p.BaselineOnSlot, p.BaselineVisits,
		p.RecentOnSlot, p.RecentVisits,
		p.RecentRate, p.BaselineRate,
	)
}

// circularMeanMinute averages times of day on a circle, so 23:40 and 00:20
// average to midnight rather than to noon.
func circularMeanMinute(ts []time.Time) int {
	var sx, sy float64
	for _, t := range ts {
		angle := 2 * math.Pi * float64(minuteOfDay(t)) / 1440.0
		sx += math.Cos(angle)
		sy += math.Sin(angle)
	}
	if sx == 0 && sy == 0 {
		// Perfectly opposed times have no meaningful mean. Fall back to the
		// first observation rather than emitting a fake midnight.
		return minuteOfDay(ts[0])
	}
	angle := math.Atan2(sy, sx)
	if angle < 0 {
		angle += 2 * math.Pi
	}
	m := int(math.Round(angle / (2 * math.Pi) * 1440.0))
	return ((m % 1440) + 1440) % 1440
}

func countOnSlot(ts []time.Time, anchor int) int {
	n := 0
	for _, t := range ts {
		if circularDistance(minuteOfDay(t), anchor) <= slotToleranceMinutes {
			n++
		}
	}
	return n
}

// circularDistance measures minutes apart the short way round the clock, so
// 23:30 and 00:30 are 60 minutes apart, not 1380.
func circularDistance(a, b int) int {
	d := a - b
	if d < 0 {
		d = -d
	}
	if d > 720 {
		d = 1440 - d
	}
	return d
}

func minuteOfDay(t time.Time) int { return t.Hour()*60 + t.Minute() }

// distinctWeeks counts how many separate ISO weeks the visits fall in — twelve
// visits crammed into one week is not a rhythm (FR-09 §2).
func distinctWeeks(ts []time.Time) int {
	seen := map[string]struct{}{}
	for _, t := range ts {
		y, w := t.ISOWeek()
		seen[fmt.Sprintf("%d-%02d", y, w)] = struct{}{}
	}
	return len(seen)
}

// weekdayBitmap renders which days were used, Sunday first: '.MTWT..'.
func weekdayBitmap(ts []time.Time) string {
	letters := []byte("SMTWTFS")
	out := []byte(".......")
	for _, t := range ts {
		d := int(t.Weekday())
		out[d] = letters[d]
	}
	return string(out)
}

func formatMinute(m int) string {
	h, min := m/60, m%60
	suffix := "am"
	dh := h
	switch {
	case h == 0:
		dh = 12
	case h == 12:
		suffix = "pm"
	case h > 12:
		dh, suffix = h-12, "pm"
	}
	return fmt.Sprintf("%d:%02d%s", dh, min, suffix)
}
