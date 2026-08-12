package devseed

import (
	"math/rand"
	"testing"
)

// The bug this pins: the segment counts were four literals summing to 150
// while memberCountTarget said 800, so seeding an empty database panicked on
// assignments[150]. It stayed invisible because the seeder skips a database
// that already has users — it only fires on a genuine reseed.
func TestSegmentAssignmentsCoversEveryMember(t *testing.T) {
	got := segmentAssignments(rand.New(rand.NewSource(42)))

	if len(got) != memberCountTarget {
		t.Fatalf("seedMembers indexes assignments[i] for i < %d, so this must "+
			"be exactly that long; got %d", memberCountTarget, len(got))
	}
}

// The mix is the point of choosing up front rather than rolling per member.
func TestSegmentAssignmentsKeepsTheMix(t *testing.T) {
	counts := map[segment]int{}
	for _, s := range segmentAssignments(rand.New(rand.NewSource(42))) {
		counts[s]++
	}

	for _, c := range []struct {
		seg  segment
		want int
	}{
		{segExpiringSoon, memberCountTarget * 15 / 100},
		{segUpcoming, memberCountTarget * 10 / 100},
		{segExpired, memberCountTarget * 15 / 100},
	} {
		if counts[c.seg] != c.want {
			t.Errorf("segment %v: want %d, got %d", c.seg, c.want, counts[c.seg])
		}
	}

	// Healthy absorbs the rounding remainder, so it is defined as whatever is
	// left rather than as its own percentage.
	used := counts[segExpiringSoon] + counts[segUpcoming] + counts[segExpired]
	if counts[segHealthy] != memberCountTarget-used {
		t.Errorf("healthy should take the remainder %d, got %d",
			memberCountTarget-used, counts[segHealthy])
	}
}
