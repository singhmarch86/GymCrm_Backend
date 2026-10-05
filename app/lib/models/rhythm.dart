/// Rhythm-break detection (FR-09).
///
/// Members who train at a consistent *time* form a habit, and the habit breaks
/// before the attendance does. These models carry the numbers behind that
/// claim, so the screen can show why a member was flagged instead of asking
/// staff to trust a score.
library;

/// Result of running a rhythm scan.
class RhythmScanResult {
  final String asOf;
  final int evaluated;
  final int eligible;
  final int broken;
  final int alertsRaised;
  final int alertsResolved;

  const RhythmScanResult({
    required this.asOf,
    required this.evaluated,
    required this.eligible,
    required this.broken,
    required this.alertsRaised,
    required this.alertsResolved,
  });

  factory RhythmScanResult.fromJson(Map<String, dynamic> j) => RhythmScanResult(
    asOf: j['as_of'] as String? ?? '',
    evaluated: j['evaluated'] as int? ?? 0,
    eligible: j['eligible'] as int? ?? 0,
    broken: j['broken'] as int? ?? 0,
    alertsRaised: j['alerts_raised'] as int? ?? 0,
    alertsResolved: j['alerts_resolved'] as int? ?? 0,
  );

  /// Deliberately mentions how many members were *eligible*, not just how many
  /// broke: "0 rhythm breaks" out of 0 eligible members means the gym has no
  /// members with an established pattern yet, which is a completely different
  /// message from "0 out of 40" and staff should not confuse the two.
  String get summaryLine {
    if (eligible == 0) {
      return 'No member has enough of a pattern yet to judge — '
          'this needs about 3 months of check-ins.';
    }
    if (alertsRaised == 0 && broken == 0) {
      return '$eligible members have a settled routine, and all of them are keeping it.';
    }
    final parts = <String>[];
    if (alertsRaised > 0) {
      parts.add(
        '$alertsRaised new rhythm break${alertsRaised == 1 ? '' : 's'}',
      );
    }
    if (broken > alertsRaised) {
      parts.add('${broken - alertsRaised} already flagged');
    }
    if (alertsResolved > 0) parts.add('$alertsResolved back on track');
    return '${parts.join(', ')} — out of $eligible members with a settled routine.';
  }
}

/// The shared numbers behind a rhythm, used by both the alert row and the
/// member profile card.
class RhythmStats {
  final int anchorMinute;
  final String usualTime;
  final int baselineVisits;
  final int baselineOnSlot;
  final double baselineConsistency;
  final double baselineRate;
  final int recentVisits;
  final int recentOnSlot;
  final double recentConsistency;
  final double recentRate;
  final String baselineWeekdays;
  final String recentWeekdays;

  const RhythmStats({
    required this.anchorMinute,
    required this.usualTime,
    required this.baselineVisits,
    required this.baselineOnSlot,
    required this.baselineConsistency,
    required this.baselineRate,
    required this.recentVisits,
    required this.recentOnSlot,
    required this.recentConsistency,
    required this.recentRate,
    required this.baselineWeekdays,
    required this.recentWeekdays,
  });

  static double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;

  factory RhythmStats.fromJson(Map<String, dynamic> j) => RhythmStats(
    anchorMinute: j['anchor_minute'] as int? ?? 0,
    usualTime: j['usual_time'] as String? ?? '',
    baselineVisits: j['baseline_visits'] as int? ?? 0,
    baselineOnSlot: j['baseline_on_slot'] as int? ?? 0,
    baselineConsistency: _d(j['baseline_consistency']),
    baselineRate: _d(j['baseline_rate']),
    recentVisits: j['recent_visits'] as int? ?? 0,
    recentOnSlot: j['recent_on_slot'] as int? ?? 0,
    recentConsistency: _d(j['recent_consistency']),
    recentRate: _d(j['recent_rate']),
    baselineWeekdays: j['baseline_weekdays'] as String? ?? '.......',
    recentWeekdays: j['recent_weekdays'] as String? ?? '.......',
  );

  int get baselinePct => (baselineConsistency * 100).round();
  int get recentPct => (recentConsistency * 100).round();

  /// Whether they are still coming as often as before. This is the sentence
  /// that makes the signal early rather than late, so it gets its own getter.
  bool get attendanceHolding => recentRate >= baselineRate * 0.9;

  /// Spelled out rather than "1.5/week now, was 1.8" — the bare numbers read
  /// as a percentage or a score unless the unit is stated.
  String get rateLine =>
      '${recentRate.toStringAsFixed(1)} visits a week now, '
      'against ${baselineRate.toStringAsFixed(1)} a week before';
}

/// An open rhythm-break alert, with the member it belongs to.
class RhythmBreak {
  final int alertId;
  final int memberId;
  final String memberName;
  final String? phone;
  final String severity;
  final String message;
  final DateTime? createdAt;
  final RhythmStats stats;

  const RhythmBreak({
    required this.alertId,
    required this.memberId,
    required this.memberName,
    required this.phone,
    required this.severity,
    required this.message,
    required this.createdAt,
    required this.stats,
  });

  factory RhythmBreak.fromJson(Map<String, dynamic> j) => RhythmBreak(
    alertId: j['alert_id'] as int? ?? 0,
    memberId: j['member_id'] as int? ?? 0,
    memberName: (j['member_name'] as String? ?? '').trim(),
    phone: j['phone'] as String?,
    severity: j['severity'] as String? ?? 'low',
    message: j['message'] as String? ?? '',
    createdAt: DateTime.tryParse(j['created_at'] as String? ?? ''),
    stats: RhythmStats.fromJson(j),
  );
}

/// One member's rhythm, whether or not it has broken.
class RhythmProfile {
  final int memberId;
  final bool isBroken;
  final int baselineWeeks;
  final RhythmStats stats;

  const RhythmProfile({
    required this.memberId,
    required this.isBroken,
    required this.baselineWeeks,
    required this.stats,
  });

  factory RhythmProfile.fromJson(Map<String, dynamic> j) => RhythmProfile(
    memberId: j['member_id'] as int? ?? 0,
    isBroken: j['is_broken'] as bool? ?? false,
    baselineWeeks: j['baseline_weeks'] as int? ?? 0,
    stats: RhythmStats.fromJson(j),
  );
}
