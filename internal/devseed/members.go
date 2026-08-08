package devseed

import (
	"fmt"
	"math/rand"
	"strings"
	"time"

	"gymcrm/internal/members"
	"gymcrm/internal/plans"
)

// Sized for a large club rather than a small studio, so list screens, search
// and the reporting queries are exercised under realistic pressure. Note this
// does not make any of the analytics "smarter" — they are per-member
// statistics, not trained models — it only makes the demo look like a real
// business and surfaces performance problems that 150 rows would hide.
const memberCountTarget = 800

// segment buckets a seeded member's renewal urgency at seed time. It maps
// onto members.dto.go's ExpiryStatus, which is computed at request time
// from Status + ExpiryDate — this seeder doesn't need to store the bucket
// anywhere, it just needs to land each member's dates in the right range.
type segment int

const (
	segHealthy      segment = iota // active, > 30 days out (or as close as the plan's duration allows)
	segExpiringSoon                // active, 1-7 days out
	segUpcoming                    // active, 8-30 days out
	segExpired                     // expired, 1-60 days in the past
)

// seedMember carries the generated member plus the metadata attendance.go
// and billing.go need: which plan funded it, and the full renewal-cycle
// history that produced its current start/expiry dates.
type seedMember struct {
	members.Member
	Segment     segment
	Plan        plans.MembershipPlan
	CycleStarts []time.Time // chronological: CycleStarts[0] is the join date
}

var maleFirstNames = []string{
	"Amanpreet", "Jaspreet", "Harpreet", "Gurpreet", "Manpreet", "Rajinder", "Sukhwinder",
	"Baljeet", "Dilpreet", "Karamjeet", "Ranjit", "Sarabjeet", "Navdeep", "Jagdeep", "Simranjeet",
	"Arshdeep", "Balwinder", "Gurjeet", "Harjot", "Manjeet", "Parminder", "Tejinder", "Yuvraj",
	"Rohit", "Vikas", "Sandeep", "Rahul", "Anil", "Deepak", "Vikram",
}

var femaleFirstNames = []string{
	"Simran", "Jasleen", "Harleen", "Gurleen", "Manleen", "Rajwinder", "Sukhman",
	"Baljeet", "Dilpreet", "Karamjot", "Ranjot", "Sarabjot", "Navjot", "Jagjot", "Simrat",
	"Arshjot", "Balpreet", "Gurpreet", "Harjeet", "Manjot", "Parminder", "Tejleen", "Yuvika",
	"Pooja", "Neha", "Priya", "Anjali", "Kiran", "Sunita", "Rekha",
}

var lastNames = []string{
	"Singh", "Kaur", "Sharma", "Gupta", "Verma", "Kapoor", "Chawla", "Bhatia", "Malhotra",
	"Arora", "Chopra", "Khanna", "Sethi", "Grewal", "Sandhu", "Bajwa", "Dhillon", "Brar",
	"Mann", "Sidhu",
}

var localities = []string{
	"Model Town Extension", "Sarabha Nagar", "Civil Lines", "BRS Nagar", "Ferozepur Road",
	"Pakhowal Road", "Dugri", "Rajguru Nagar", "Sunet", "Gill Road", "Haibowal Kalan",
	"Salem Tabri", "Jamalpur", "Shimlapuri", "Tajpur Road",
}

// exactCounts sums to memberCountTarget — chosen up front (rather than
// per-member weighted rolls) so the 60/15/10/15 mix in the plan is exact,
// not just approximate.
func segmentAssignments(rng *rand.Rand) []segment {
	assignments := make([]segment, 0, memberCountTarget)
	counts := map[segment]int{
		segHealthy:      90,
		segExpiringSoon: 22,
		segUpcoming:     15,
		segExpired:      23,
	}
	for seg, n := range counts {
		for i := 0; i < n; i++ {
			assignments = append(assignments, seg)
		}
	}
	return assignments
}

func (s *seeder) seedMembers() error {
	assignments := segmentAssignments(s.rng)
	s.rng.Shuffle(len(assignments), func(i, j int) {
		assignments[i], assignments[j] = assignments[j], assignments[i]
	})

	planWeights := []float64{0.35, 0.25, 0.15, 0.10, 0.15} // Monthly, Quarterly, Half Yearly, Annual, PT Package

	for i := 0; i < memberCountTarget; i++ {
		isFemale := s.rng.Intn(2) == 0
		var first string
		var gender string
		if isFemale {
			first = pick(s.rng, femaleFirstNames)
			gender = "female"
		} else {
			first = pick(s.rng, maleFirstNames)
			gender = "male"
		}
		if s.rng.Intn(30) == 0 {
			gender = "other"
		}
		last := pick(s.rng, lastNames)

		planIdx := weightedIndex(s.rng, planWeights)
		plan := s.plans[planIdx]
		d := plan.DurationDays

		seg := assignments[i]
		daysRemaining := dayRangeFor(s.rng, seg, d)

		lastRenewalDate := s.now.AddDate(0, 0, daysRemaining-d)
		expiryDate := lastRenewalDate.AddDate(0, 0, d)

		status := members.MemberStatusActive
		if daysRemaining < 0 {
			status = members.MemberStatusExpired
		}

		totalCycles := 1 + s.rng.Intn(4)
		cycleStarts := make([]time.Time, totalCycles)
		cycleStarts[totalCycles-1] = lastRenewalDate
		for k := totalCycles - 2; k >= 0; k-- {
			cycleStarts[k] = cycleStarts[k+1].AddDate(0, 0, -d)
		}
		joinDate := cycleStarts[0]

		phone := fmt.Sprintf("90%08d", 1000000+i)
		email := strings.ToLower(fmt.Sprintf("%s.%s%d@gmail.com", first, last, i))
		address := fmt.Sprintf("House No. %d, %s, Ludhiana", 100+i, pick(s.rng, localities))

		member := members.Member{
			GymID:            s.gymID,
			FirstName:        first,
			LastName:         last,
			Phone:            phone,
			Email:            strPtr(email),
			Gender:           strPtr(gender),
			Address:          strPtr(address),
			MembershipPlanID: int64Ptr(plan.ID),
			StartDate:        timePtr(lastRenewalDate),
			ExpiryDate:       timePtr(expiryDate),
			Status:           status,
			CreatedAt:        joinDate,
			UpdatedAt:        joinDate,
		}
		if err := s.tx.Create(&member).Error; err != nil {
			return fmt.Errorf("create member %d: %w", i, err)
		}

		s.members = append(s.members, seedMember{
			Member:      member,
			Segment:     seg,
			Plan:        plan,
			CycleStarts: cycleStarts,
		})
	}

	s.memberCount = len(s.members)
	return nil
}

// dayRangeFor returns a random days-remaining value inside the segment's
// bucket, matching the ExpiryStatus buckets in internal/members/dto.go.
//
// segHealthy is the one bucket whose target (>30 days out) can exceed what
// a member's own plan duration d physically allows — you can't be 300 days
// from expiry on a 30-day Monthly plan. Rather than clamping every such
// member down to exactly "renewed today" (which piles every one of them
// onto the same renewal_date), it spreads the last renewal uniformly
// across the member's current cycle, so days-remaining lands anywhere in
// [1, d]: still "active", still spread out, even when d itself is small.
func dayRangeFor(rng *rand.Rand, seg segment, d int) int {
	switch seg {
	case segHealthy:
		renewedDaysAgo := rng.Intn(d)
		return d - renewedDaysAgo
	case segExpiringSoon:
		return 1 + rng.Intn(7)
	case segUpcoming:
		return 8 + rng.Intn(30-8+1)
	case segExpired:
		return -(1 + rng.Intn(60))
	default:
		return 0
	}
}
