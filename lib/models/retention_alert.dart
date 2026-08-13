/// A churn-risk alert raised by the retention scan.
/// Maps backend retention.AlertRow.
class RetentionAlert {
  final int id;
  final int memberId;
  final String memberName;
  final String phone;
  final String alertType;
  final String severity; // low | medium | high
  final String message; // pre-rendered, ready to send
  final bool isResolved;
  final String createdAt;

  /// Who handled it and what they did. Null means unknown — either the scan
  /// auto-resolved it, or it was closed before we recorded this.
  final String? resolvedByName;
  final String? actionNote;

  RetentionAlert({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.phone,
    required this.alertType,
    required this.severity,
    required this.message,
    required this.isResolved,
    required this.createdAt,
    this.resolvedByName,
    this.actionNote,
  });

  factory RetentionAlert.fromJson(Map<String, dynamic> j) => RetentionAlert(
    id: j['id'] ?? 0,
    memberId: j['member_id'] ?? 0,
    memberName: j['member_name'] ?? '',
    phone: j['phone'] ?? '',
    alertType: j['alert_type'] ?? '',
    severity: j['severity'] ?? 'low',
    message: j['message'] ?? '',
    isResolved: j['is_resolved'] ?? false,
    createdAt: j['created_at'] ?? '',
    resolvedByName: j['resolved_by_name'],
    actionNote: j['action_note'],
  );

  /// Human label for the reason this alert exists.
  String get typeLabel => switch (alertType) {
    'expiring_in_3_days' => 'Expiring in 3 days',
    'expiring_today' => 'Expires today',
    'expired_no_renewal' => 'Expired, not renewed',
    'inactive_1_week' => 'Inactive 1 week',
    'inactive_2_weeks' => 'Inactive 2+ weeks',
    'rhythm_break' => 'Routine broken',
    _ => alertType.replaceAll('_', ' '),
  };

  /// True for the lapse/renewal family, false for the attendance family —
  /// used to pick an icon that matches the kind of problem.
  bool get isExpiryRelated => alertType.startsWith('expir');
}

/// Result of running a scan. Maps backend retention.ScanResult.
class ScanResult {
  final int raised;
  final int resolved;
  final int skipped;

  ScanResult({
    required this.raised,
    required this.resolved,
    required this.skipped,
  });

  factory ScanResult.fromJson(Map<String, dynamic> j) => ScanResult(
    raised: j['raised'] ?? 0,
    resolved: j['resolved'] ?? 0,
    skipped: j['skipped'] ?? 0,
  );

  /// Phrased so a scan that changes nothing still reads as a useful outcome
  /// ("nothing new") rather than an apparent failure.
  String get summaryLine {
    if (raised == 0 && resolved == 0) {
      return skipped > 0
          ? 'No changes — $skipped alert${skipped == 1 ? '' : 's'} still open'
          : 'No members are currently at risk';
    }
    final parts = <String>[];
    if (raised > 0) parts.add('$raised new');
    if (resolved > 0) parts.add('$resolved auto-resolved');
    return parts.join(' · ');
  }
}

/// Open alert counts by severity + when the last scan ran.
class RetentionSummary {
  final int high;
  final int medium;
  final int low;
  final int total;
  final String? lastScanAt;

  RetentionSummary({
    required this.high,
    required this.medium,
    required this.low,
    required this.total,
    this.lastScanAt,
  });

  factory RetentionSummary.fromJson(Map<String, dynamic> j) {
    final counts = (j['counts'] as Map?) ?? {};
    return RetentionSummary(
      high: (counts['high'] ?? 0) as int,
      medium: (counts['medium'] ?? 0) as int,
      low: (counts['low'] ?? 0) as int,
      total: j['total'] ?? 0,
      lastScanAt: j['last_scan_at'],
    );
  }
}

/// One alert a staff member closed — the evidence behind their count.
class HandledItem {
  final int alertId;
  final int memberId;
  final String memberName;
  final String alertType;
  final String? actionNote;
  final String resolvedAt;

  HandledItem({
    required this.alertId,
    required this.memberId,
    required this.memberName,
    required this.alertType,
    this.actionNote,
    required this.resolvedAt,
  });

  factory HandledItem.fromJson(Map<String, dynamic> j) => HandledItem(
    alertId: j['alert_id'] ?? 0,
    memberId: j['member_id'] ?? 0,
    memberName: j['member_name'] ?? '',
    alertType: j['alert_type'] ?? '',
    actionNote: j['action_note'],
    resolvedAt: j['resolved_at'] ?? '',
  );

  /// Short reason label, matching RetentionAlert.typeLabel.
  String get typeLabel => switch (alertType) {
    'expiring_in_3_days' => 'Expiring soon',
    'expiring_today' => 'Expires today',
    'expired_no_renewal' => 'Lapsed',
    'inactive_1_week' => 'Inactive 1wk',
    'inactive_2_weeks' => 'Inactive 2wk+',
    'rhythm_break' => 'Routine broken',
    _ => alertType.replaceAll('_', ' '),
  };

  String get relativeTime {
    try {
      final d = DateTime.parse(resolvedAt).toLocal();
      final diff = DateTime.now().difference(d);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }
}

/// How many alerts a staff member has cleared in a window.
/// Maps backend retention.StaffActivity.
class StaffActivity {
  /// Null when the alerts were auto-resolved by the scan, or closed before
  /// resolved_by existed. Deliberately not collapsed into a person.
  final int? userId;
  final String? name;
  final int resolvedCount;

  /// The most recent items behind [resolvedCount] — capped server-side, so
  /// this is a sample, not necessarily the full list.
  final List<HandledItem> recent;

  StaffActivity({
    this.userId,
    this.name,
    required this.resolvedCount,
    this.recent = const [],
  });

  factory StaffActivity.fromJson(Map<String, dynamic> j) => StaffActivity(
    userId: j['user_id'],
    name: j['name'],
    resolvedCount: j['resolved_count'] ?? 0,
    recent: (j['recent'] as List? ?? [])
        .map((e) => HandledItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  /// True when no human did this — the system closed it because the member
  /// renewed or came back. Shown separately so it never reads as someone's work.
  bool get isSystem => userId == null || (name == null || name!.isEmpty);

  String get label => isSystem ? 'Resolved automatically' : name!;
}
