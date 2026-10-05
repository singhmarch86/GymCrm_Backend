package activation

import (
	"strings"
	"testing"
	"time"
)

// The bug this pins: an alert raised yesterday kept saying "joined 3 days ago"
// while the row beside it counted 4. Two numbers disagreeing on one card is
// the kind of small wrongness that makes somebody distrust the whole screen.
func TestMessageIsRenderedFromLiveNumbers(t *testing.T) {
	now := time.Date(2026, 8, 10, 9, 0, 0, 0, time.UTC)

	row := AlertRow{
		MemberName:    "Krishna Gupta",
		AlertType:     string(StateNoFirstVisit),
		DaysSinceJoin: 4, // live count today
		Visits:        0,
		// What was stored yesterday, when it really was 3 days.
		Message: "Krishna Gupta joined 3 days ago and has not checked in once.",
	}

	got := renderMessage(row, now)

	if !strings.Contains(got, "4 days ago") {
		t.Fatalf("message did not pick up the live day count: %q", got)
	}
	if strings.Contains(got, "3 days ago") {
		t.Fatalf("message still replays the stale stored text: %q", got)
	}
}

func TestGoingQuietMessageUsesLiveSilenceLength(t *testing.T) {
	now := time.Date(2026, 8, 10, 9, 0, 0, 0, time.UTC)
	last := time.Date(2026, 7, 27, 18, 0, 0, 0, time.UTC) // 14 days back

	row := AlertRow{
		MemberName:    "Rohit Arora",
		AlertType:     string(StateGoingQuiet),
		DaysSinceJoin: 50,
		Visits:        6,
		LastVisit:     &last,
		Message:       "stale text from when the gap was 10 days",
	}

	got := renderMessage(row, now)
	if !strings.Contains(got, "14 days ago") {
		t.Fatalf("expected the live 14-day gap, got %q", got)
	}
}

func TestUnknownStateFallsBackToTheStoredMessage(t *testing.T) {
	// If a row somehow carries a type this package cannot phrase, showing the
	// stored sentence is far better than showing an empty card.
	row := AlertRow{
		MemberName: "Someone",
		AlertType:  "some_future_alert_type",
		Message:    "the original wording",
	}
	if got := renderMessage(row, time.Now()); got != "the original wording" {
		t.Fatalf("expected the stored message as fallback, got %q", got)
	}
}
