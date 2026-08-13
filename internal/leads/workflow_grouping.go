package leads

import "sort"

// Categorising the follow-up queue (FR-24).
//
// The queue has always grouped by timing — unattended, overdue, today,
// upcoming — which answers "what is late". It could not answer "what kind of
// work is waiting", or "which sources are we failing to follow up", and those
// are different questions with different owners: the first is the desk's, the
// second is the person who decides where the marketing money goes.
//
// No new taxonomy is invented here, deliberately. Three ways of categorising a
// lead already exist in the schema:
//
//	next_step  seven types from FR-18, which the pilot gym is expected to
//	           correct once they have watched a real week
//	source     where the lead came from
//	goal       what they said they wanted
//
// Inventing a fourth — objection reasons, temperature, tiers — before the gym
// has been asked would be guessing at their vocabulary and then asking them to
// live inside it.

// GroupBy names the axis the queue is cut along.
type GroupBy string

const (
	// The original, and still the default: what is late.
	GroupByTiming GroupBy = "timing"

	// What kind of work is owed.
	GroupByNextStep GroupBy = "next_step"

	// Where the lead came from, and what they wanted.
	GroupBySource GroupBy = "source"
	GroupByGoal   GroupBy = "goal"
)

var AllGroupBys = []GroupBy{
	GroupByTiming, GroupByNextStep, GroupBySource, GroupByGoal,
}

func (g GroupBy) Label() string {
	switch g {
	case GroupByNextStep:
		return "What needs doing"
	case GroupBySource:
		return "Where they came from"
	case GroupByGoal:
		return "What they want"
	}
	return "What is late"
}

// ParseGroupBy accepts an empty value as the default rather than an error.
// A client that has not been updated should keep getting the queue it has
// always got.
func ParseGroupBy(raw string) (GroupBy, bool) {
	if raw == "" {
		return GroupByTiming, true
	}
	for _, g := range AllGroupBys {
		if string(g) == raw {
			return g, true
		}
	}
	return "", false
}

// stateRank orders items inside a category group.
//
// Timing does not stop mattering because the reader asked to see the queue by
// source. Within "Instagram" the unattended leads still come first, so cutting
// the queue a different way never buries the thing that was most urgent.
func stateRank(state string) int {
	switch WorkflowState(state) {
	case StateUnattended:
		return 0
	case StateOverdue:
		return 1
	case StateToday:
		return 2
	}
	return 3
}

// groupByField cuts the items along one of the lead's own attributes.
//
// Items with nothing in the field are collected into a named group rather than
// dropped. On this gym's data every single lead has an empty next_step, so a
// version that hid them would show an empty screen and imply there was no work
// — when what it actually means is that nobody has recorded what the work is.
func groupByField(
	items []WorkflowItem,
	key func(WorkflowItem) string,
	label func(string) string,
	emptyLabel string,
	order []string,
) []WorkflowGroup {
	buckets := map[string][]WorkflowItem{}
	for _, it := range items {
		buckets[key(it)] = append(buckets[key(it)], it)
	}

	for k := range buckets {
		sort.SliceStable(buckets[k], func(a, b int) bool {
			return stateRank(buckets[k][a].State) < stateRank(buckets[k][b].State)
		})
	}

	out := make([]WorkflowGroup, 0, len(buckets)+1)

	// The known values first, in their declared order, including the ones with
	// nothing in them. An empty "Referral" group is the useful sentence "no
	// referrals are waiting", and a group that vanishes at zero denies it —
	// the same rule the timing groups follow.
	seen := map[string]bool{}
	for _, k := range order {
		seen[k] = true
		out = append(out, WorkflowGroup{
			State: k,
			Label: label(k),
			Count: len(buckets[k]),
			Items: buckets[k],
		})
	}

	// Anything the code did not know about — a source somebody typed by hand,
	// a next step from a future release. Shown rather than silently lost.
	var extras []string
	for k := range buckets {
		if !seen[k] && k != "" {
			extras = append(extras, k)
		}
	}
	sort.Strings(extras)
	for _, k := range extras {
		out = append(out, WorkflowGroup{
			State: k,
			Label: label(k),
			Count: len(buckets[k]),
			Items: buckets[k],
		})
	}

	if rest := buckets[""]; len(rest) > 0 {
		out = append(out, WorkflowGroup{
			State: "unset",
			Label: emptyLabel,
			Count: len(rest),
			Items: rest,
		})
	}

	return out
}

func nextStepKeys() []string {
	out := make([]string, 0, len(AllNextSteps))
	for _, s := range AllNextSteps {
		out = append(out, string(s))
	}
	return out
}

// Sources and goals are not enumerated in Go — they are free-ish columns the
// gym can extend — so the declared order is the set seen in practice, and
// anything else arrives through the extras path above.
var knownSources = []string{
	"walk_in", "referral", "whatsapp", "instagram", "facebook", "google",
}

var knownGoals = []string{
	"weight_loss", "muscle_gain", "fitness", "sports", "rehab",
}

// prettify turns a stored key into something readable without a lookup table
// per column: "weight_loss" becomes "Weight loss". Values the gym adds later
// therefore read correctly with no code change.
func prettify(raw string) string {
	if raw == "" {
		return "Not recorded"
	}
	b := []rune(raw)
	out := make([]rune, 0, len(b))
	for i, r := range b {
		if r == '_' {
			out = append(out, ' ')
			continue
		}
		if i == 0 {
			if r >= 'a' && r <= 'z' {
				r -= 32
			}
		}
		out = append(out, r)
	}
	return string(out)
}
