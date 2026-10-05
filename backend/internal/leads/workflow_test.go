package leads

import (
	"testing"
	"time"
)

var ist = time.FixedZone("IST", 5*60*60+30*60)

func today() time.Time { return time.Date(2026, 8, 12, 10, 0, 0, 0, ist) }

func leadWith(status LeadStatus, step *string, due *time.Time, owner *int64) *Lead {
	return &Lead{Status: status, NextStep: step, NextStepDue: due, AssignedUserID: owner}
}

func ptr[T any](v T) *T { return &v }

// The state this whole feature exists to surface: a lead nobody picked up.
func TestALeadWithNoStepIsUnattended(t *testing.T) {
	l := leadWith(LeadStatusContacted, nil, nil, ptr(int64(1)))
	if got := StateOf(l, today()); got != StateUnattended {
		t.Fatalf("state = %q, want unattended", got)
	}
}

// A step with no date is as invisible as no step: nobody is ever reminded.
func TestAStepWithNoDateIsStillUnattended(t *testing.T) {
	l := leadWith(LeadStatusContacted, ptr("book_trial"), nil, ptr(int64(1)))
	if got := StateOf(l, today()); got != StateUnattended {
		t.Fatalf("state = %q, want unattended", got)
	}
}

// And so is a step nobody owns.
func TestAnUnownedStepIsUnattended(t *testing.T) {
	due := today()
	l := leadWith(LeadStatusContacted, ptr("book_trial"), &due, nil)
	if got := StateOf(l, today()); got != StateUnattended {
		t.Fatalf("state = %q, want unattended", got)
	}
}

func TestDueDatesClassifyAgainstTheGymsDay(t *testing.T) {
	owner := ptr(int64(1))
	step := ptr("book_trial")

	cases := []struct {
		name string
		due  time.Time
		want WorkflowState
	}{
		{"yesterday", today().AddDate(0, 0, -1), StateOverdue},
		{"today", today(), StateToday},
		{"tomorrow", today().AddDate(0, 0, 1), StateUpcoming},
	}
	for _, c := range cases {
		due := c.due
		l := leadWith(LeadStatusContacted, step, &due, owner)
		if got := StateOf(l, today()); got != c.want {
			t.Fatalf("%s: state = %q, want %q", c.name, got, c.want)
		}
	}
}

// A due date at 23:00 IST is still "today" — comparison is by calendar day,
// not by instant, or every evening's work would read as overdue.
func TestLateInTheDayIsStillToday(t *testing.T) {
	due := time.Date(2026, 8, 12, 23, 30, 0, 0, ist)
	l := leadWith(LeadStatusContacted, ptr("book_trial"), &due, ptr(int64(1)))
	if got := StateOf(l, today()); got != StateToday {
		t.Fatalf("state = %q, want today", got)
	}
}

// FR-18 §6: nothing nags about a member who already joined.
func TestJoinedAndLostAreClosedEvenWithAStepSet(t *testing.T) {
	stale := today().AddDate(0, 0, -30)
	for _, st := range []LeadStatus{LeadStatusJoined, LeadStatusLost} {
		l := leadWith(st, ptr("book_trial"), &stale, ptr(int64(1)))
		if got := StateOf(l, today()); got != StateClosed {
			t.Fatalf("%s: state = %q, want closed", st, got)
		}
	}
}

func TestDefaultStepsExistForEveryOpenStageAndNoClosedOne(t *testing.T) {
	for _, st := range []LeadStatus{
		LeadStatusNew, LeadStatusContacted,
		LeadStatusTrialScheduled, LeadStatusTrialCompleted,
	} {
		step, _, ok := DefaultStepFor(st)
		if !ok {
			t.Fatalf("%s has no default step — leads would arrive unattended", st)
		}
		if !IsValidNextStep(string(step)) {
			t.Fatalf("%s maps to invalid step %q", st, step)
		}
	}
	for _, st := range []LeadStatus{LeadStatusJoined, LeadStatusLost} {
		if _, _, ok := DefaultStepFor(st); ok {
			t.Fatalf("%s must not carry a next step", st)
		}
	}
}

// A cold lead is perishable: first contact is due the same day, not tomorrow.
func TestFirstContactIsDueSameDay(t *testing.T) {
	step, days, _ := DefaultStepFor(LeadStatusNew)
	if step != StepFirstContact || days != 0 {
		t.Fatalf("got %q in %d days, want first_contact same day", step, days)
	}
}

func TestSuggestionsCoverEveryOutcome(t *testing.T) {
	for _, o := range AllOutcomes {
		s, ok := SuggestNext(o, today(), nil)
		if !ok {
			t.Fatalf("%s produced no suggestion", o)
		}
		if !IsValidNextStep(string(s.Step)) {
			t.Fatalf("%s suggested invalid step %q", o, s.Step)
		}
		if s.Reason == "" {
			t.Fatalf("%s suggested %q with no reason — an unexplained "+
				"suggestion gets accepted without thought", o, s.Step)
		}
	}
}

// Calling twice in an hour is how a gym becomes the number nobody answers.
func TestNoAnswerRetriesTomorrowNotToday(t *testing.T) {
	s, _ := SuggestNext(OutcomeNoAnswer, today(), nil)
	if !s.Due.After(today()) {
		t.Fatalf("due %v should be after today", s.Due)
	}
}

// When the member has told us when to call, that beats any default.
func TestCallBackUsesTheDateTheyAskedFor(t *testing.T) {
	asked := today().AddDate(0, 0, 9)
	s, _ := SuggestNext(OutcomeCallBack, today(), &asked)
	if !s.Due.Equal(asked) {
		t.Fatalf("due = %v, want the requested %v", s.Due, asked)
	}

	// With no date given it still suggests something rather than nothing.
	s2, ok := SuggestNext(OutcomeCallBack, today(), nil)
	if !ok || s2.Step != StepCallBack {
		t.Fatalf("got %q/%v, want a call_back suggestion", s2.Step, ok)
	}
}

// FR-16 §4 / FR-18 §3: suggesting a close is not closing.
func TestNotInterestedSuggestsClosingWithoutClosing(t *testing.T) {
	s, _ := SuggestNext(OutcomeNotInterested, today(), nil)
	if s.Step != StepClose {
		t.Fatalf("step = %q, want close", s.Step)
	}
	// Nothing in this package may mutate a lead's status. If SuggestNext ever
	// grows a *Lead parameter, that is the moment this rule quietly dies.
}

func TestInvalidStepsAreRejected(t *testing.T) {
	for _, bad := range []string{"", "negotiation", "'; DROP TABLE leads; --"} {
		if IsValidNextStep(bad) {
			t.Fatalf("%q should not be a valid next step", bad)
		}
	}
}

func TestEveryStepAndStateHasALabel(t *testing.T) {
	for _, s := range AllNextSteps {
		if got := s.Label(); got == "" || got == string(s) {
			t.Fatalf("step %q has no human label", s)
		}
	}
	for _, w := range []WorkflowState{
		StateUnattended, StateOverdue, StateToday, StateUpcoming, StateClosed,
	} {
		if got := w.Label(); got == "" || got == string(w) {
			t.Fatalf("state %q has no human label", w)
		}
	}
}

// Counselling must be loggable by staff, or FR-18 §4 is decorative.
func TestCounsellingIsAClientLoggableActivity(t *testing.T) {
	if !IsValidActivityType(string(ActivityCounselling)) {
		t.Fatal("counselling must be submittable by a client")
	}
	if !ActivityCounselling.AcceptsOutcome() {
		t.Fatal("counselling should accept an outcome")
	}
	// Server-written history still must not be.
	if IsValidActivityType(string(ActivityStageChange)) {
		t.Fatal("stage_change must stay server-only")
	}
}
