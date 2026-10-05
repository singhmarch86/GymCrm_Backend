// Package entitlements gates individual features behind the pricing
// sheet's three tiers (Normal / Medium / Premium — see docs/manual-deck's
// Quick Reference for the feature list this was built from). It has no
// dependency on any other internal package's DB models — callers pass in
// a TierProvider, so entitlements never needs to know what a Gym struct
// looks like.
package entitlements

import "fmt"

// Tier is a pricing plan. The three values are additive, exactly as the
// pricing sheet describes them ("Everything in Normal, plus...",
// "Everything in Medium, plus...") — there is no tier that unlocks a
// Medium feature without also carrying every Normal one.
type Tier string

const (
	TierNormal  Tier = "normal"
	TierMedium  Tier = "medium"
	TierPremium Tier = "premium"
)

// rank gives every tier a comparable position — Normal < Medium < Premium.
// Unexported: nothing outside this file needs to know tiers are backed by
// integers, only that they can be compared.
var rank = map[Tier]int{
	TierNormal:  0,
	TierMedium:  1,
	TierPremium: 2,
}

// atLeast reports whether tier meets or exceeds min — an unknown tier
// (typoed in the DB, or a row this migration hasn't reached) ranks below
// everything, so it fails every gate rather than accidentally passing one.
func (t Tier) atLeast(min Tier) bool {
	r, ok := rank[t]
	if !ok {
		return false
	}
	minRank, ok := rank[min]
	if !ok {
		return false
	}
	return r >= minRank
}

// ParseTier validates a raw string (as stored in gyms.plan_tier) into a
// Tier — the one place a plain string from the database becomes the typed
// value everything else in this package works with.
func ParseTier(raw string) (Tier, error) {
	t := Tier(raw)
	if _, ok := rank[t]; !ok {
		return "", fmt.Errorf("entitlements: unknown tier %q", raw)
	}
	return t, nil
}
