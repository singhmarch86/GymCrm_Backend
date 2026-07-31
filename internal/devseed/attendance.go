package devseed

import (
	"time"

	"gymcrm/internal/attendance"
	"gymcrm/internal/members"
)

const attendanceWindowDays = 90

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

		switch attendancePattern(pattern) {
		case patternDaily:
			for d := start; !d.After(end); d = d.AddDate(0, 0, 1) {
				if s.rng.Float64() < 0.85 {
					rows = append(rows, s.checkIn(m.ID, d))
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
					rows = append(rows, s.checkIn(m.ID, d))
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

func (s *seeder) checkIn(memberID int64, day time.Time) attendance.Attendance {
	hour := 6 + s.rng.Intn(15) // gym hours: 6am-9pm
	minute := s.rng.Intn(60)
	checkedInAt := time.Date(day.Year(), day.Month(), day.Day(), hour, minute, 0, 0, time.UTC)
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
