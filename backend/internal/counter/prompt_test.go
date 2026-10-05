package counter

import (
	"strings"
	"testing"
)

func base() Context {
	return Context{
		TotalVisits:        40,
		DaysSinceLastVisit: 2,
		RecentKinds:        map[Kind]bool{},
	}
}

func TestSilenceIsTheNormalAnswer(t *testing.T) {
	// A regular member with nothing going on must produce nothing. If this
	// ever starts returning a prompt, the feature is dead within a week.
	if got := Decide(base()); !got.IsEmpty() {
		t.Fatalf("expected silence, got %q: %s", got.Kind, got.Text)
	}
}

func TestFirstVisitWins(t *testing.T) {
	c := base()
	c.TotalVisits = 1
	c.DaysSinceLastVisit = -1
	// Even with everything else competing for the slot.
	c.OpenAlerts = []OpenAlert{{"expiring_today", "high", "Expires today"}}
	c.PT = &PTPackage{TrainerName: "Rahul", SessionsLeft: 1}

	got := Decide(c)
	if got.Kind != KindFirstVisit {
		t.Fatalf("kind = %q, want %q", got.Kind, KindFirstVisit)
	}
}

func TestWelcomeBackBeatsTheGoneQuietAlert(t *testing.T) {
	// The whole point: the alert says "chase them", but they are standing at
	// the counter. Getting this wrong has staff interrogating somebody who
	// just did the hard thing and came back.
	c := base()
	c.DaysSinceLastVisit = 24
	c.OpenAlerts = []OpenAlert{
		{"activation_going_quiet", "high", "They stopped coming"},
		{"inactive_2_weeks", "high", "Haven't seen you in a while"},
	}

	got := Decide(c)
	if got.Kind != KindWelcomeBack {
		t.Fatalf("kind = %q, want %q", got.Kind, KindWelcomeBack)
	}
	if !strings.Contains(got.Text, "24 days") {
		t.Fatalf("text should say how long: %q", got.Text)
	}
}

func TestInactivityAlertsNeverReachTheCounter(t *testing.T) {
	// Member is standing here after a 3-day gap, so welcome_back does not
	// apply — but an inactivity alert must still never be shown, because
	// telling the desk "they have not been coming" is absurd.
	c := base()
	c.OpenAlerts = []OpenAlert{{"inactive_1_week", "high", "Haven't seen you"}}

	if got := Decide(c); !got.IsEmpty() {
		t.Fatalf("expected silence, got %q: %s", got.Kind, got.Text)
	}
}

func TestMostSevereAlertWins(t *testing.T) {
	c := base()
	c.OpenAlerts = []OpenAlert{
		{"rhythm_break", "low", "low one"},
		{"expiring_today", "high", "high one"},
		{"activation_slow_start", "medium", "medium one"},
	}
	got := Decide(c)
	if got.Kind != KindAlert || got.Text != "high one" {
		t.Fatalf("got %q / %q, want the high-severity alert", got.Kind, got.Text)
	}
}

func TestPriorityOrderIsAlertThenPTThenRestockThenWallet(t *testing.T) {
	c := base()
	c.OpenAlerts = []OpenAlert{{"expiring_today", "high", "Expires today"}}
	c.PT = &PTPackage{TrainerName: "Rahul", SessionsLeft: 1}
	c.Restock = &RestockCandidate{"Whey", 4, 31, 30}
	c.UsesWallet = true
	c.WalletBalanceInPaise = 5000

	if got := Decide(c); got.Kind != KindAlert {
		t.Fatalf("kind = %q, want alert to win", got.Kind)
	}

	c.OpenAlerts = nil
	if got := Decide(c); got.Kind != KindPTLow {
		t.Fatalf("kind = %q, want pt_low next", got.Kind)
	}

	c.PT = nil
	if got := Decide(c); got.Kind != KindRestock {
		t.Fatalf("kind = %q, want restock next", got.Kind)
	}

	c.Restock = nil
	if got := Decide(c); got.Kind != KindWalletLow {
		t.Fatalf("kind = %q, want wallet_low last", got.Kind)
	}
}

func TestCooldownSuppressesTheSameKind(t *testing.T) {
	// Somebody who trains daily must not be told about their protein tub six
	// days running — that is how staff learn to ignore the panel.
	c := base()
	c.Restock = &RestockCandidate{"Whey", 4, 31, 30}
	if got := Decide(c); got.Kind != KindRestock {
		t.Fatalf("setup wrong: kind = %q", got.Kind)
	}

	c.RecentKinds[KindRestock] = true
	if got := Decide(c); !got.IsEmpty() {
		t.Fatalf("cooldown ignored: got %q", got.Kind)
	}
}

func TestCooldownIsPerKindNotGlobal(t *testing.T) {
	// A genuinely new situation must still get through.
	c := base()
	c.RecentKinds[KindRestock] = true
	c.OpenAlerts = []OpenAlert{{"expiring_today", "high", "Expires today"}}

	if got := Decide(c); got.Kind != KindAlert {
		t.Fatalf("kind = %q, want the alert to still come through", got.Kind)
	}
}

func TestRestockNeedsTwoPurchasesAndAnElapsedInterval(t *testing.T) {
	c := base()
	// One purchase says nothing about an interval.
	c.Restock = &RestockCandidate{"Whey", 1, 60, 30}
	if got := Decide(c); !got.IsEmpty() {
		t.Fatalf("single purchase should not prompt, got %q", got.Kind)
	}
	// Not yet due.
	c.Restock = &RestockCandidate{"Whey", 5, 12, 30}
	if got := Decide(c); !got.IsEmpty() {
		t.Fatalf("not due yet should not prompt, got %q", got.Kind)
	}
}

func TestWalletOnlyForMembersWhoUseIt(t *testing.T) {
	c := base()
	c.WalletBalanceInPaise = 0

	// A zero balance on somebody who has never used the wallet is not news.
	c.UsesWallet = false
	if got := Decide(c); !got.IsEmpty() {
		t.Fatalf("expected silence for a non-wallet member, got %q", got.Kind)
	}

	c.UsesWallet = true
	if got := Decide(c); got.Kind != KindWalletLow {
		t.Fatalf("kind = %q, want wallet_low", got.Kind)
	}
}

func TestPTNotPromptedWhenExhaustedOrPlentiful(t *testing.T) {
	c := base()
	c.PT = &PTPackage{TrainerName: "Rahul", SessionsLeft: 0}
	if got := Decide(c); !got.IsEmpty() {
		t.Fatalf("an exhausted package is not a low-sessions prompt, got %q", got.Kind)
	}
	c.PT = &PTPackage{TrainerName: "Rahul", SessionsLeft: 8}
	if got := Decide(c); !got.IsEmpty() {
		t.Fatalf("8 sessions left should not prompt, got %q", got.Kind)
	}
}

func TestNothingEverMentionsMoneyOwed(t *testing.T) {
	// FR-11 §6: dues are deliberately never a counter prompt. There are other
	// people within earshot.
	c := base()
	c.OpenAlerts = []OpenAlert{{"expiring_today", "high", "Expires today"}}
	c.UsesWallet = true
	c.WalletBalanceInPaise = 100

	for _, got := range []Prompt{Decide(c)} {
		lower := strings.ToLower(got.Text)
		for _, banned := range []string{"owe", "outstanding", "due amount", "pending payment"} {
			if strings.Contains(lower, banned) {
				t.Fatalf("prompt mentions money owed: %q", got.Text)
			}
		}
	}
}

func TestDoubleTapDoesNotShowTheSameMomentTwice(t *testing.T) {
	// A staff member tapping check-in twice must not log the welcome-back
	// moment twice — that would corrupt the effectiveness numbers, which are
	// the only way to ever tell whether any of this works.
	c := base()
	c.DaysSinceLastVisit = 24
	if got := Decide(c); got.Kind != KindWelcomeBack {
		t.Fatalf("setup wrong: kind = %q", got.Kind)
	}

	c.RecentKinds[KindWelcomeBack] = true
	if got := Decide(c); got.Kind == KindWelcomeBack {
		t.Fatal("welcome_back shown twice inside the cooldown")
	}

	// Same for a first visit.
	f := base()
	f.TotalVisits = 1
	f.DaysSinceLastVisit = -1
	f.RecentKinds[KindFirstVisit] = true
	if got := Decide(f); got.Kind == KindFirstVisit {
		t.Fatal("first_visit shown twice")
	}
}

func TestRupeesRendersWholeRupees(t *testing.T) {
	if got := rupees(15000); got != "₹150" {
		t.Fatalf("rupees(15000) = %q, want ₹150", got)
	}
}
