/// Renewals due (FR-19 §4) — money the gym is about to be owed.
///
/// This is what "expected payments" turned out to be. Nothing is scheduled
/// forward into the payments table, so the only forward-looking signal is a
/// membership expiry date.
library;

class RenewalItem {
  final int memberId;
  final String member;
  final String phone;

  final int? planId;
  final String? planName;
  final int? planInPaise;

  final DateTime? expiryDate;

  /// Negative means it has already passed. Read from the server rather than
  /// recomputed, so the grouping and the label can never disagree.
  final int daysUntilExpiry;

  /// A member who stopped coming three weeks before expiry is a different
  /// conversation from one who trained yesterday.
  final DateTime? lastVisitAt;

  /// Outstanding money on the same member. Renewing somebody who already owes
  /// is a decision, not an oversight.
  final int owedInPaise;

  final int previousRenewals;

  const RenewalItem({
    required this.memberId,
    required this.member,
    required this.phone,
    this.planId,
    this.planName,
    this.planInPaise,
    this.expiryDate,
    required this.daysUntilExpiry,
    this.lastVisitAt,
    required this.owedInPaise,
    required this.previousRenewals,
  });

  factory RenewalItem.fromJson(Map<String, dynamic> j) => RenewalItem(
    memberId: j['member_id'] ?? 0,
    member: j['member'] ?? '',
    phone: j['phone'] ?? '',
    planId: j['plan_id'],
    planName: j['plan_name'],
    planInPaise: j['plan_in_paise'],
    expiryDate: _date(j['expiry_date']),
    daysUntilExpiry: j['days_until_expiry'] ?? 0,
    lastVisitAt: _date(j['last_visit_at']),
    owedInPaise: j['owed_in_paise'] ?? 0,
    previousRenewals: j['previous_renewals'] ?? 0,
  );

  bool get hasLapsed => daysUntilExpiry < 0;
  bool get owesMoney => owedInPaise > 0;

  /// Days since they last came in. Null when they never have — which is its
  /// own, worse, signal.
  int? get daysSinceVisit {
    final v = lastVisitAt;
    if (v == null) return null;
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(v.year, v.month, v.day)).inDays;
  }

  static DateTime? _date(dynamic v) {
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v)?.toLocal();
  }
}

class RenewalGroup {
  final String key;
  final String label;
  final String note;
  final String severity;
  final List<RenewalItem> items;
  final int valueInPaise;

  const RenewalGroup({
    required this.key,
    required this.label,
    required this.note,
    required this.severity,
    required this.items,
    required this.valueInPaise,
  });

  factory RenewalGroup.fromJson(Map<String, dynamic> j) => RenewalGroup(
    key: j['key'] ?? '',
    label: j['label'] ?? '',
    note: j['note'] ?? '',
    severity: j['severity'] ?? 'normal',
    items: ((j['items'] as List?) ?? [])
        .map((e) => RenewalItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    valueInPaise: j['value_in_paise'] ?? 0,
  );
}

class RenewalQueue {
  final List<RenewalGroup> groups;
  final int windowDays;
  final int totalCount;
  final int valueInPaise;

  /// Lapsed longer ago than the window. Counted, never listed — and never
  /// silently dropped, which is why it has its own field.
  final int beyondWindow;

  const RenewalQueue({
    required this.groups,
    required this.windowDays,
    required this.totalCount,
    required this.valueInPaise,
    required this.beyondWindow,
  });

  factory RenewalQueue.fromJson(Map<String, dynamic> j) => RenewalQueue(
    groups: ((j['groups'] as List?) ?? [])
        .map((e) => RenewalGroup.fromJson(e as Map<String, dynamic>))
        .toList(),
    windowDays: j['window_days'] ?? 30,
    totalCount: j['total_count'] ?? 0,
    valueInPaise: j['value_in_paise'] ?? 0,
    beyondWindow: j['beyond_window'] ?? 0,
  );

  bool get isClear => totalCount == 0;
}
