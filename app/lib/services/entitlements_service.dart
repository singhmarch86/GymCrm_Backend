import 'storage_service.dart';

/// A pricing plan. Mirrors internal/entitlements.Tier on the backend
/// exactly — additive, same as the pricing sheet describes them
/// ("Everything in Normal, plus...", "Everything in Medium, plus...").
enum Tier { normal, medium, premium }

extension TierRank on Tier {
  int get _rank => switch (this) {
    Tier.normal => 0,
    Tier.medium => 1,
    Tier.premium => 2,
  };

  bool atLeast(Tier min) => _rank >= min._rank;
}

Tier _parseTier(String? raw) => switch (raw) {
  'normal' => Tier.normal,
  'medium' => Tier.medium,
  'premium' => Tier.premium,
  // Unknown/missing (a session saved before this field existed, or a typo)
  // fails open to Premium — matches the backend migration's own default,
  // so an existing session never loses a feature it already had just
  // because the app couldn't read its tier yet.
  _ => Tier.premium,
};

/// One line item from the pricing sheet — mirrors
/// internal/entitlements.Feature on the backend. Keep this list and
/// [_minTier] in exact sync with that file's catalog; a Feature missing
/// there is a bug the same way it is server-side.
///
/// Reports and Leads were tagged piece by piece with the owner: Revenue and
/// Members reports and the basic Leads CRM are on every plan (no Feature);
/// the rest below are Medium. Still not here: "Owner-level reports", "Full
/// audit / history" and "Advanced staff controls" (not mapped to a screen).
enum Feature {
  retentionSignals,
  counterPrompts,
  moneyLeaks,
  digitalWallet,
  shopPos,
  classes,
  ptPackages,
  trainerFeedback,
  recognition,
  staffWork,
  multiBranch,
  advancedPayouts,
  reportPayments,
  reportRenewals,
  reportPlans,
  leadsBoard,
  leadsWorkflow,
  leadsFollowUps,
  leadAnalytics,
}

const Map<Feature, Tier> _minTier = {
  Feature.retentionSignals: Tier.medium,
  Feature.counterPrompts: Tier.medium,
  Feature.moneyLeaks: Tier.medium,
  Feature.digitalWallet: Tier.medium,
  Feature.shopPos: Tier.medium,
  Feature.classes: Tier.medium,
  Feature.ptPackages: Tier.medium,
  Feature.trainerFeedback: Tier.medium,
  Feature.recognition: Tier.medium,
  Feature.staffWork: Tier.medium,
  Feature.multiBranch: Tier.premium,
  Feature.advancedPayouts: Tier.premium,
  Feature.reportPayments: Tier.medium,
  Feature.reportRenewals: Tier.medium,
  Feature.reportPlans: Tier.medium,
  Feature.leadsBoard: Tier.medium,
  Feature.leadsWorkflow: Tier.medium,
  Feature.leadsFollowUps: Tier.medium,
  Feature.leadAnalytics: Tier.medium,
};

/// The one place the app asks "does this gym's plan include X". A plain
/// static cache, not a ChangeNotifier — nothing in this app rebuilds
/// reactively on entitlement changes today (a plan upgrade takes effect
/// next time a screen is opened, which is the nav grid on every visit to
/// More/the shell anyway), so a stream would be complexity nothing reads.
class EntitlementsService {
  EntitlementsService._();

  static Tier _tier = Tier.premium;

  /// Reads the cached tier from storage. Call once, early — see
  /// splash_screen.dart, right before an existing session opens AppShell.
  static Future<void> load() async {
    _tier = _parseTier(await StorageService.getPlanTier());
  }

  /// Sets the tier directly from a fresh login/register response, so the
  /// very first screen after signing in already reflects it without
  /// waiting on a storage round trip.
  static void setTier(String? raw) {
    _tier = _parseTier(raw);
  }

  static Tier get tier => _tier;

  /// True for a Feature with no entry in [_minTier] — an ungated feature,
  /// or one this app hasn't been taught to gate yet, is available to
  /// everyone rather than silently hidden.
  static bool has(Feature feature) {
    final min = _minTier[feature];
    if (min == null) return true;
    return _tier.atLeast(min);
  }
}
