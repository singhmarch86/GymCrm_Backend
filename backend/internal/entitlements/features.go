package entitlements

// Feature is one line item from the pricing sheet, mapped to whichever
// existing module actually implements it.
//
// Reports and Leads were tagged piece by piece with the owner (2026-10-05):
// Revenue and Members reports plus the basic Leads CRM (list, add/edit,
// assign, stage moves, convert) stay on every plan, so they have no Feature;
// the pieces below are Medium. Still NOT here: "Owner-level reports", "Full
// audit / history" and "Advanced staff controls", which have not been mapped
// to a concrete screen yet. "Priority support" and "Data migration /
// onboarding" aren't software at all (human service), so they have no
// Feature and never will.
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

	FeatureReportPayments Feature = "report_payments" // Reports: payment-mode distribution
	FeatureReportRenewals Feature = "report_renewals" // Reports: renewal success rate + trend
	FeatureReportPlans    Feature = "report_plans"    // Reports: plan distribution + per-plan performance
	FeatureLeadsBoard     Feature = "leads_board"     // Leads pipeline board — UI only: it reads GET /leads like the list does, so no route can carry the gate
	FeatureLeadsWorkflow  Feature = "leads_workflow"  // Leads workflow queue, next-step options and setting a next step
	FeatureLeadsFollowUps Feature = "leads_followups" // Leads follow-up queue
	FeatureLeadAnalytics  Feature = "lead_analytics"  // Lead funnel, sources, lost reasons, conversion

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
	FeatureReportPayments:   TierMedium,
	FeatureReportRenewals:   TierMedium,
	FeatureReportPlans:      TierMedium,
	FeatureLeadsBoard:       TierMedium,
	FeatureLeadsWorkflow:    TierMedium,
	FeatureLeadsFollowUps:   TierMedium,
	FeatureLeadAnalytics:    TierMedium,

	FeatureMultiBranch:     TierPremium,
	FeatureAdvancedPayouts: TierPremium,
}
