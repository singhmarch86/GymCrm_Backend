package counter

import (
	"fmt"
	"time"
)

// The rules from docs/FR-11, kept free of database and HTTP so the priority
// order — which is the whole design — can be tested exactly.

// Tunables (FR-11 §8).
const (
	// Matches FR-10's going-quiet threshold on purpose, so the two features
	// never disagree about the same member.
	welcomeBackDays = 10

	// Enough warning to sell the next block without nagging from session five.
	ptSessionsLow = 2

	// Roughly one counter purchase.
	walletLowPaise = 20000

	// The most important number here. If staff start ignoring the panel, raise
	// this first (FR-11 §4).
	cooldownDays = 7

	// One purchase tells you nothing about an interval.
	minPurchasesForRestock = 2
)

// Kind identifies which rule produced the prompt.
type Kind string

const (
	KindNone        Kind = ""
	KindFirstVisit  Kind = "first_visit"
	KindWelcomeBack Kind = "welcome_back"
	KindAlert       Kind = "alert"
	KindPTLow       Kind = "pt_low"
	KindRestock     Kind = "restock"
	KindWalletLow   Kind = "wallet_low"
)

// Prompt is the single line the desk sees. Zero value means say nothing, which
// is the normal outcome (FR-11 §2).
type Prompt struct {
	Kind Kind   `json:"kind"`
	Text string `json:"text"`
}

func (p Prompt) IsEmpty() bool { return p.Kind == KindNone }

// OpenAlert is an unresolved alert for this member.
type OpenAlert struct {
	AlertType string
	Severity  string
	Message   string
}

// PTPackage is an active personal-training package.
type PTPackage struct {
	TrainerName  string
	SessionsLeft int
}

// RestockCandidate is a consumable the member buys repeatedly.
type RestockCandidate struct {
	ProductName   string
	Purchases     int
	DaysSinceLast int
	TypicalDays   int // their own average gap between purchases
}

// Context is everything known about the member at the moment they check in.
type Context struct {
	TotalVisits          int
	DaysSinceLastVisit   int // -1 if this is their first ever visit
	OpenAlerts           []OpenAlert
	PT                   *PTPackage
	Restock              *RestockCandidate
	WalletBalanceInPaise int64
	UsesWallet           bool

	// RecentKinds are prompt kinds already shown to this member inside the
	// cooldown window.
	RecentKinds map[Kind]bool
}

// Decide returns the one prompt worth showing, or an empty prompt.
//
// The order below IS the specification (FR-11 §3): first match wins, and
// nothing accumulates.
func Decide(c Context) Prompt {
	// 1. Their first ever visit. The moment everything downstream depends on,
	//    and the one nobody currently marks.
	if c.TotalVisits <= 1 && c.DaysSinceLastVisit < 0 && !c.RecentKinds[KindFirstVisit] {
		return Prompt{KindFirstVisit,
			"First visit. Make sure someone shows them round and books their next session."}
	}

	// 2. Back after a long absence.
	//
	//    This deliberately outranks their own "went quiet" alert. That alert
	//    says chase this person — but they are standing at the counter, so
	//    chasing is over and the script is completely different. Without this
	//    rule the desk would interrogate somebody who just did the hard thing
	//    and came back.
	//
	//    The cooldown applies here too. The 10-day absence looked like enough
	//    of a natural limit on its own, but it is not: a staff member who taps
	//    check-in twice would log the moment twice, which quietly corrupts the
	//    only measurement that can ever say whether these prompts work.
	if c.DaysSinceLastVisit >= welcomeBackDays && !c.RecentKinds[KindWelcomeBack] {
		return Prompt{KindWelcomeBack, fmt.Sprintf(
			"First time back in %d days. Say welcome back — don't ask where they've been.",
			c.DaysSinceLastVisit)}
	}

	// 3. An open alert, most severe first. Inactivity alerts are skipped: rule
	//    2 already describes this member better, and they are here anyway.
	if !c.RecentKinds[KindAlert] {
		if a, ok := pickAlert(c.OpenAlerts); ok {
			return Prompt{KindAlert, a.Message}
		}
	}

	// 4. Personal training nearly used up — an honest ask at the only moment
	//    they are thinking about training.
	if c.PT != nil && c.PT.SessionsLeft > 0 && c.PT.SessionsLeft <= ptSessionsLow &&
		!c.RecentKinds[KindPTLow] {
		return Prompt{KindPTLow, fmt.Sprintf(
			"%d PT session%s left with %s. Good moment to ask about the next block.",
			c.PT.SessionsLeft, plural(c.PT.SessionsLeft), c.PT.TrainerName)}
	}

	// 5. About to run out of something they buy from you. If they run out they
	//    buy it elsewhere, and often don't come back to your counter.
	if r := c.Restock; r != nil && !c.RecentKinds[KindRestock] &&
		r.Purchases >= minPurchasesForRestock &&
		r.TypicalDays > 0 && r.DaysSinceLast >= r.TypicalDays {
		return Prompt{KindRestock, fmt.Sprintf(
			"Last bought %s %d days ago — they buy about every %d.",
			r.ProductName, r.DaysSinceLast, r.TypicalDays)}
	}

	// 6. Wallet low, but only for members who actually use it. A zero balance
	//    on somebody who has never used the wallet is not news.
	if c.UsesWallet && c.WalletBalanceInPaise < walletLowPaise &&
		!c.RecentKinds[KindWalletLow] {
		return Prompt{KindWalletLow, fmt.Sprintf(
			"Wallet balance %s. Top up?", rupees(c.WalletBalanceInPaise))}
	}

	// 7. Nothing. By far the most common outcome, and the point (FR-11 §2).
	return Prompt{}
}

// pickAlert returns the most severe alert worth mentioning at the counter.
func pickAlert(alerts []OpenAlert) (OpenAlert, bool) {
	rank := map[string]int{"high": 0, "medium": 1, "low": 2}
	best := -1
	for i, a := range alerts {
		// The member is standing here — telling the desk they have not been
		// coming would be absurd, and rule 2 has already handled it.
		if a.AlertType == "inactive_1_week" || a.AlertType == "inactive_2_weeks" ||
			a.AlertType == "activation_going_quiet" {
			continue
		}
		if best < 0 || rank[a.Severity] < rank[alerts[best].Severity] {
			best = i
		}
	}
	if best < 0 {
		return OpenAlert{}, false
	}
	return alerts[best], true
}

func plural(n int) string {
	if n == 1 {
		return ""
	}
	return "s"
}

// rupees renders paise as ₹1,500 — whole rupees, since a counter prompt with
// paise precision reads like a bill.
func rupees(paise int64) string {
	return fmt.Sprintf("₹%d", paise/100)
}

// CooldownSince is the cutoff for "already shown recently" (FR-11 §4).
func CooldownSince(now time.Time) time.Time {
	return now.AddDate(0, 0, -cooldownDays)
}
