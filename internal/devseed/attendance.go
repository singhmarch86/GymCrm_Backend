package devseed

import (
	"time"

	"gymcrm/internal/attendance"
	"gymcrm/internal/members"
)

const attendanceWindowDays = 90

// Check-in times are generated in India Standard Time, not UTC. Building them
// in UTC — as this file used to — put a "7am" check-in at 12:30pm local, which
// made every time-of-day feature read nonsense.
var istLocation = time.FixedZone("IST", 5*60*60+30*60)

// Real gyms have two peaks and a quiet middle. A uniform 6am-9pm spread, which
// is what this seeder produced before, is the one distribution no gym has —
// and it makes rhythm-break detection (FR-09) untestable, because nobody in
// the data has a rhythm to break.
var slotBands = []struct {
	weight  float64
	fromMin int
	toMin   int
}{
	{0.40, 6*60 + 0, 7*60 + 45},    // before work
	{0.12, 9*60 + 30, 11*60 + 30},  // mid-morning: homemakers, shift workers
	{0.06, 12*60 + 30, 14*60 + 0},  // lunch
	{0.42, 17*60 + 30, 20*60 + 30}, // after work
}

// attendanceRhythm is how a member's check-in *times* behave, independent of
// how often they come.
type attendanceRhythm struct {
	// slotMinute is the member's habitual time, minutes past local midnight.
	slotMinute int
	// punctual members hold that slot; free-floaters come whenever they can
	// and are never flagged by rhythm-break detection, by design.
	punctual bool
	// breaksFrom, when non-zero, is the day a punctual member's routine falls
	// apart while their visit frequency stays the same — the exact cohort
	// FR-09 exists to catch, and the reason it is worth seeding at all.
	breaksFrom time.Time
}

// attendancePattern is how often a member showed up over the seeded window.
type attendancePattern int

const (
	patternDaily     attendancePattern = iota // ~85% of days
	patternTwiceWeek                          // 2 random weekdays per week
	patternInactive                           // no check-ins at all
)

// seedAttendance generates the last 90 days of check-ins per member. Each
// member gets a random pattern (daily / twice-a-week / inactive), and the
// window is clamped to [member's join date, today] — or to the member's
// expiry date for expired members, since they stopped coming once their
// membership lapsed. That clamp is what makes an "expired" member also show
// up as genuinely inactive once a churn/inactivity query is built on top of
// this data.
func (s *seeder) seedAttendance() error {
	windowStart := s.now.AddDate(0, 0, -(attendanceWindowDays - 1))

	var rows []attendance.Attendance

	for i := range s.members {
		m := &s.members[i]

		start := windowStart
		if m.CycleStarts[0].After(start) {
			start = m.CycleStarts[0]
		}
		end := s.now
		if m.Status == members.MemberStatusExpired && m.ExpiryDate != nil && m.ExpiryDate.Before(end) {
			end = *m.ExpiryDate
		}
		if end.Before(start) {
			continue // member joined and expired outside the 90-day window entirely
		}

		pattern := weightedIndex(s.rng, []float64{0.20, 0.50, 0.30})
		rhythm := s.pickRhythm()

		switch attendancePattern(pattern) {
		case patternDaily:
			for d := start; !d.After(end); d = d.AddDate(0, 0, 1) {
				if s.rng.Float64() < 0.85 {
					rows = append(rows, s.checkIn(m.ID, d, rhythm))
				}
			}
		case patternTwiceWeek:
			for weekStart := start; !weekStart.After(end); weekStart = weekStart.AddDate(0, 0, 7) {
				weekEnd := weekStart.AddDate(0, 0, 6)
				if weekEnd.After(end) {
					weekEnd = end
				}
				days := daysBetween(weekStart, weekEnd)
				if len(days) == 0 {
					continue
				}
				s.rng.Shuffle(len(days), func(a, b int) { days[a], days[b] = days[b], days[a] })
				for _, d := range days[:minInt(2, len(days))] {
					rows = append(rows, s.checkIn(m.ID, d, rhythm))
				}
			}
		case patternInactive:
			// no check-ins — this is the "inactive" cohort the PRD asks for
		}
	}

	if len(rows) == 0 {
		return nil
	}
	if err := s.tx.CreateInBatches(rows, 200).Error; err != nil {
		return err
	}
	s.attendanceCount = len(rows)
	return nil
}

// pickRhythm assigns one member their habitual training time and how firmly
// they hold it.
func (s *seeder) pickRhythm() attendanceRhythm {
	band := slotBands[weightedIndex(s.rng, []float64{
		slotBands[0].weight, slotBands[1].weight,
		slotBands[2].weight, slotBands[3].weight,
	})]

	r := attendanceRhythm{
		slotMinute: band.fromMin + s.rng.Intn(band.toMin-band.fromMin+1),
		// Most gym members are creatures of habit; the rest are the
		// free-floaters FR-09 deliberately never flags.
		punctual: s.rng.Float64() < 0.72,
	}

	// About one punctual member in eight has lost their slot recently. Kept
	// low on purpose: if a third of the gym were flagged the screen would be
	// noise, and the demo would teach the wrong lesson about the feature.
	if r.punctual && s.rng.Float64() < 0.12 {
		r.breaksFrom = s.now.AddDate(0, 0, -(18 + s.rng.Intn(8)))
	}
	return r
}

func (s *seeder) checkIn(memberID int64, day time.Time, r attendanceRhythm) attendance.Attendance {
	scattered := !r.punctual ||
		(!r.breaksFrom.IsZero() && !day.Before(r.breaksFrom))

	var minuteOfDay int
	if scattered {
		// Whenever they can fit it in: anywhere across opening hours.
		minuteOfDay = 6*60 + s.rng.Intn(15*60)
	} else {
		// Around their slot. A ~22-minute spread keeps almost every visit
		// inside the ±90-minute window FR-09 treats as "kept the slot", while
		// still looking like a human rather than a cron job.
		minuteOfDay = r.slotMinute + int(s.rng.NormFloat64()*22)
		if minuteOfDay < 5*60+30 {
			minuteOfDay = 5*60 + 30
		}
		if minuteOfDay > 22*60+30 {
			minuteOfDay = 22*60 + 30
		}
	}

	checkedInAt := time.Date(day.Year(), day.Month(), day.Day(), 0, 0, 0, 0, istLocation).
		Add(time.Duration(minuteOfDay) * time.Minute)

	return attendance.Attendance{
		GymID:         s.gymID,
		MemberID:      memberID,
		CheckedInAt:   checkedInAt,
		CheckedInDate: day,
	}
}

func daysBetween(start, end time.Time) []time.Time {
	var days []time.Time
	for d := start; !d.After(end); d = d.AddDate(0, 0, 1) {
		days = append(days, d)
	}
	return days
}
