/// First 90 days: activation (FR-10).
///
/// A gym loses more members in their first three months than any other period,
/// and usually not because they were unhappy — because they never actually
/// started. These models carry what was observed, so the screen can say what
/// happened rather than show a score.
library;

/// Result of running an activation scan.
class ActivationScanResult {
  final int inProgramme;
  final int onTrack;
  final int frozen;
  final int neverStarted;
  final int slowStart;
  final int goingQuiet;
  final int alertsRaised;
  final int alertsResolved;

  const ActivationScanResult({
    required this.inProgramme,
    required this.onTrack,
    required this.frozen,
    required this.neverStarted,
    required this.slowStart,
    required this.goingQuiet,
    required this.alertsRaised,
    required this.alertsResolved,
  });

  factory ActivationScanResult.fromJson(Map<String, dynamic> j) =>
      ActivationScanResult(
        inProgramme: j['in_programme'] as int? ?? 0,
        onTrack: j['on_track'] as int? ?? 0,
        frozen: j['frozen'] as int? ?? 0,
        neverStarted: j['never_started'] as int? ?? 0,
        slowStart: j['slow_start'] as int? ?? 0,
        goingQuiet: j['going_quiet'] as int? ?? 0,
        alertsRaised: j['alerts_raised'] as int? ?? 0,
        alertsResolved: j['alerts_resolved'] as int? ?? 0,
      );

  int get needAttention => neverStarted + slowStart + goingQuiet;

  /// Phrased around how many new members there are, not just how many are
  /// failing: "0 problems" out of 0 new members means something completely
  /// different from "0 out of 40", and staff must not confuse the two.
  String get summaryLine {
    if (inProgramme == 0) {
      return 'No members joined in the last 90 days.';
    }
    if (needAttention == 0) {
      return 'All $inProgramme new members are settling in fine.';
    }
    final parts = <String>[];
    if (neverStarted > 0) parts.add('$neverStarted never came in');
    if (goingQuiet > 0) parts.add('$goingQuiet went quiet');
    if (slowStart > 0) parts.add('$slowStart coming too rarely');
    return '${parts.join(', ')} — of $inProgramme members in their first 90 days.';
  }
}

/// One open activation alert.
class ActivationAlert {
  final int alertId;
  final int memberId;
  final String memberName;
  final String? phone;
  final String alertType;
  final String severity;
  final String message;
  final int daysSinceJoin;
  final int visits;
  final DateTime? lastVisit;
  final double visitsPerWeek;

  const ActivationAlert({
    required this.alertId,
    required this.memberId,
    required this.memberName,
    required this.phone,
    required this.alertType,
    required this.severity,
    required this.message,
    required this.daysSinceJoin,
    required this.visits,
    required this.lastVisit,
    required this.visitsPerWeek,
  });

  factory ActivationAlert.fromJson(Map<String, dynamic> j) => ActivationAlert(
        alertId: j['alert_id'] as int? ?? 0,
        memberId: j['member_id'] as int? ?? 0,
        memberName: (j['member_name'] as String? ?? '').trim(),
        phone: j['phone'] as String?,
        alertType: j['alert_type'] as String? ?? '',
        severity: j['severity'] as String? ?? 'low',
        message: j['message'] as String? ?? '',
        daysSinceJoin: j['days_since_join'] as int? ?? 0,
        visits: j['visits'] as int? ?? 0,
        lastVisit: DateTime.tryParse(j['last_visit'] as String? ?? ''),
        visitsPerWeek: (j['visits_per_week'] as num?)?.toDouble() ?? 0,
      );

  /// Each state is a different phone call, so each gets its own label.
  String get typeLabel => switch (alertType) {
        'activation_no_first_visit' => 'Never came in',
        'activation_going_quiet' => 'Started, then stopped',
        'activation_slow_start' => 'Too rarely to stick',
        _ => alertType.replaceAll('_', ' '),
      };

  /// What the staff member is actually being asked to do.
  String get callToAction => switch (alertType) {
        'activation_no_first_visit' =>
          'Get them through the door once. Book a specific day and time.',
        'activation_going_quiet' =>
          'Find out what stopped. Then give them a fixed slot to come back to.',
        'activation_slow_start' =>
          'Ask what makes it hard to get here, and help them pick two fixed days.',
        _ => '',
      };
}

/// One join-month's activation funnel.
class ActivationCohort {
  final String joinMonth;
  final int joined;
  final int everVisited;
  final int fourInTwoWeeks;
  final int twelveInFirstMonth;
  final int activeAtSixtyToNinety;

  /// False when this cohort's first 90 days fall partly outside the check-in
  /// history the gym has. Those months read as catastrophic onboarding when
  /// nothing is wrong, so the screen must label them rather than let an owner
  /// draw the conclusion.
  final bool dataComplete;

  const ActivationCohort({
    required this.joinMonth,
    required this.joined,
    required this.everVisited,
    required this.fourInTwoWeeks,
    required this.twelveInFirstMonth,
    required this.activeAtSixtyToNinety,
    required this.dataComplete,
  });

  factory ActivationCohort.fromJson(Map<String, dynamic> j) => ActivationCohort(
        joinMonth: j['join_month'] as String? ?? '',
        joined: j['joined'] as int? ?? 0,
        everVisited: j['ever_visited'] as int? ?? 0,
        fourInTwoWeeks: j['four_in_two_weeks'] as int? ?? 0,
        twelveInFirstMonth: j['twelve_in_first_month'] as int? ?? 0,
        activeAtSixtyToNinety: j['active_at_sixty_to_ninety'] as int? ?? 0,
        dataComplete: j['data_complete'] as bool? ?? false,
      );

  double _share(int n) => joined == 0 ? 0 : n / joined;

  double get everVisitedShare => _share(everVisited);
  double get fourInTwoWeeksShare => _share(fourInTwoWeeks);
  double get twelveInFirstMonthShare => _share(twelveInFirstMonth);
  double get activeAtSixtyShare => _share(activeAtSixtyToNinety);
}
