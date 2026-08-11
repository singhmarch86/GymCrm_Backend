/// Staff work dashboard (FR-13).
///
/// What happened today, and who did it. Every number here is read back out of
/// a ledger that already recorded the acting user — nothing on this screen is
/// a score, a ranking, or a target.
library;

/// One category's contribution to one person's day.
class StaffTally {
  final String category;
  final String label;
  final int count;

  /// Paise. Null — not zero — when the category moves no money. Resolving an
  /// alert is not a ₹0 achievement, and showing it as one would read as a
  /// failure.
  final int? amountInPaise;

  const StaffTally({
    required this.category,
    required this.label,
    required this.count,
    this.amountInPaise,
  });

  factory StaffTally.fromJson(Map<String, dynamic> j) => StaffTally(
        category: j['category'] as String? ?? '',
        label: j['label'] as String? ?? '',
        count: j['count'] as int? ?? 0,
        amountInPaise: j['amount_in_paise'] as int?,
      );

  bool get hasMoney => amountInPaise != null;
}

/// One person's whole day.
class StaffDay {
  /// Null for the Unattributed row — work whose ledger row carries no user.
  final int? userId;
  final String name;
  final String? role;
  final List<StaffTally> tallies;
  final int totalActions;
  final int totalHandledInPaise;
  final DateTime? firstActionAt;
  final DateTime? lastActionAt;

  const StaffDay({
    this.userId,
    required this.name,
    this.role,
    required this.tallies,
    required this.totalActions,
    required this.totalHandledInPaise,
    this.firstActionAt,
    this.lastActionAt,
  });

  factory StaffDay.fromJson(Map<String, dynamic> j) => StaffDay(
        userId: j['user_id'] as int?,
        name: j['name'] as String? ?? 'Unattributed',
        role: j['role'] as String?,
        tallies: ((j['tallies'] as List?) ?? [])
            .map((e) => StaffTally.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalActions: j['total_actions'] as int? ?? 0,
        totalHandledInPaise: j['total_handled_in_paise'] as int? ?? 0,
        firstActionAt: _parse(j['first_action_at']),
        lastActionAt: _parse(j['last_action_at']),
      );

  bool get isUnattributed => userId == null;

  /// Whether a first/last time span is worth showing.
  ///
  /// Several ledgers store a DATE rather than a timestamp — a payment's
  /// paid_date has no clock — so those rows all land on local midnight.
  /// Rendering "00:00 to 00:00" would look like a bug and tell nobody
  /// anything, so the span is suppressed unless it actually spans something.
  bool get hasRealTimeSpan {
    final a = firstActionAt, b = lastActionAt;
    if (a == null || b == null) return false;
    if (a.hour == 0 && a.minute == 0 && b.hour == 0 && b.minute == 0) {
      return false;
    }
    return b.difference(a).inMinutes.abs() >= 1;
  }

  static DateTime? _parse(dynamic v) {
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v)?.toLocal();
  }
}

/// The whole screen for one date.
class StaffWorkDay {
  final String date;
  final List<StaffDay> staff;
  final int totalActions;
  final int totalHandledInPaise;

  const StaffWorkDay({
    required this.date,
    required this.staff,
    required this.totalActions,
    required this.totalHandledInPaise,
  });

  factory StaffWorkDay.fromJson(Map<String, dynamic> j) => StaffWorkDay(
        date: j['date'] as String? ?? '',
        staff: ((j['staff'] as List?) ?? [])
            .map((e) => StaffDay.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalActions: j['total_actions'] as int? ?? 0,
        totalHandledInPaise: j['total_handled_in_paise'] as int? ?? 0,
      );

  bool get isEmpty => staff.isEmpty;
}

/// One row behind a number. An aggregate nobody can open is an accusation.
class StaffWorkItem {
  final String category;
  final DateTime at;
  final String who;
  final String what;
  final int? amountInPaise;

  const StaffWorkItem({
    required this.category,
    required this.at,
    required this.who,
    required this.what,
    this.amountInPaise,
  });

  factory StaffWorkItem.fromJson(Map<String, dynamic> j) => StaffWorkItem(
        category: j['category'] as String? ?? '',
        at: DateTime.tryParse(j['at'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
        who: j['who'] as String? ?? '',
        what: j['what'] as String? ?? '',
        amountInPaise: j['amount_in_paise'] as int?,
      );
}
