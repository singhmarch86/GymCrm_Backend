package entitlements

// Feature is one line item from the pricing sheet, mapped to whichever
// existing module actually implements it.
//
// Deliberately NOT here yet: Reports/Analytics ("Basic reports", "Basic
// dashboard", "Advanced business analytics", "More detailed reports",
// "Owner-level reports", "Full audit / history"), the Leads split ("Basic
// leads / CRM" in Normal vs "Leads pipeline + follow-up" / "Lead
// conversion analytics" in Medium), and "Advanced staff controls" — all
// of these currently live as one undivided screen in the code (internal/
// reports, internal/dashboard, internal/leads, internal/users), not one
// screen per pricing-sheet bullet. Gating them here would either gate the
// wrong thing or require splitting the screen first — worth doing
// deliberately, tag by tag, rather than guessing. "Priority support" and
// "Data migration / onboarding" aren't software at all (human service),
// so they have no Feature and never will.
type Feature string

const (
	// ── Medium ───────────────────────────────────────────────────────────
	FeatureRetentionSignals Feature = "retention_signals" // "At Risk / retention system — all 9 retention signals"
	FeatureCounterPrompts   Feature = "counter_prompts"   // "Counter prompts"
	FeatureMoneyLeaks       Feature = "money_leaks"       // "Money Leaks"
	FeatureDigitalWallet    Feature = "digital_wallet"    // "Digital Wallet"
	FeatureShopPOS          Feature = "shop_pos"          // "Shop / POS", "Stock & restock management", "Sales history / refunds"
	FeatureClasses          Feature = "classes"           // "Classes & timetable"
	FeaturePTPackages       Feature = "pt_packages"       // "PT packages & appointments"
	FeatureTrainerFeedback  Feature = "trainer_feedback"  // "Trainer management + feedback"
	FeatureRecognition      Feature = "recognition"       // "Recognition"
	FeatureStaffWork        Feature = "staff_work"        // "Staff Work"

	// ── Premium ──────────────────────────────────────────────────────────
	// Every multi-branch bullet on the sheet (management, switching,
	// transfers, targets, chain comparison, chain stock visibility,
	// multi-branch analytics, multi-location administration) is already
	// one cohesive module in the code — internal/branches — so it's one
	// Feature here too, not nine.
	FeatureMultiBranch     Feature = "multi_branch"     // "Multi-branch management" and everything else in that cluster
	FeatureAdvancedPayouts Feature = "advanced_payouts" // "Advanced trainer payouts", "Salary + commission + session-based payouts"
)

// minTier is the catalog: every gated Feature's floor tier. A Feature with
// no entry here is a bug (RequireFeature panics on lookup miss, on
// purpose — see middleware.go) rather than silently letting everyone
// through or blocking everyone.
var minTier = map[Feature]Tier{
	FeatureRetentionSignals: TierMedium,
	FeatureCounterPrompts:   TierMedium,
	FeatureMoneyLeaks:       TierMedium,
	FeatureDigitalWallet:    TierMedium,
	FeatureShopPOS:          TierMedium,
	FeatureClasses:          TierMedium,
	FeaturePTPackages:       TierMedium,
	FeatureTrainerFeedback:  TierMedium,
	FeatureRecognition:      TierMedium,
	FeatureStaffWork:        TierMedium,

	FeatureMultiBranch:     TierPremium,
	FeatureAdvancedPayouts: TierPremium,
}
