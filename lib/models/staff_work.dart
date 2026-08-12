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

/// The whole screen for one span (FR-18 §9).
class StaffWorkDay {
  /// Empty when the span covers more than one day — a month has no single
  /// date, and the server deliberately omits it rather than sending the first
  /// day for something the reader might label the whole range with.
  final String date;

  final String from;
  final String to;
  final int days;

  final List<StaffDay> staff;
  final int totalActions;
  final int totalHandledInPaise;

  const StaffWorkDay({
    required this.date,
    required this.from,
    required this.to,
    required this.days,
    required this.staff,
    required this.totalActions,
    required this.totalHandledInPaise,
  });

  factory StaffWorkDay.fromJson(Map<String, dynamic> j) => StaffWorkDay(
        date: j['date'] as String? ?? '',
        from: j['from'] as String? ?? '',
        to: j['to'] as String? ?? '',
        days: j['days'] as int? ?? 1,
        staff: ((j['staff'] as List?) ?? [])
            .map((e) => StaffDay.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalActions: j['total_actions'] as int? ?? 0,
        totalHandledInPaise: j['total_handled_in_paise'] as int? ?? 0,
      );

  bool get isEmpty => staff.isEmpty;
  bool get isSingleDay => days <= 1;
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

/// A drill-down list, plus whether it is the whole list.
///
/// A day rarely hit the cap; a month will. "Exactly 200 things happened" and
/// "the first 200 of many" look identical on screen and mean very different
/// things, so the server says which it is rather than leaving the reader to
/// assume.
class StaffWorkItems {
  final List<StaffWorkItem> items;
  final bool truncated;
  final int limit;

  const StaffWorkItems({
    required this.items,
    required this.truncated,
    required this.limit,
  });

  factory StaffWorkItems.fromJson(Map<String, dynamic> j) => StaffWorkItems(
        items: ((j['items'] as List?) ?? [])
            .map((e) => StaffWorkItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        truncated: j['truncated'] as bool? ?? false,
        limit: j['limit'] as int? ?? 0,
      );
}

/// What one person is carrying right now (FR-18 §7).
///
/// Deliberately not date-scoped: a lead nobody has picked up is unattended
/// today regardless of which day the screen is showing.
class LeadWorkload {
  final int openLeads;
  final int unattended;
  final int overdue;
  final int dueToday;
  final int? nextLeadId;
  final String? nextLeadName;
  final DateTime? nextDue;

  const LeadWorkload({
    required this.openLeads,
    required this.unattended,
    required this.overdue,
    required this.dueToday,
    this.nextLeadId,
    this.nextLeadName,
    this.nextDue,
  });

  factory LeadWorkload.fromJson(Map<String, dynamic> j) => LeadWorkload(
        openLeads: j['open_leads'] ?? 0,
        unattended: j['unattended'] ?? 0,
        overdue: j['overdue'] ?? 0,
        dueToday: j['due_today'] ?? 0,
        nextLeadId: j['next_lead_id'],
        nextLeadName: j['next_lead_name'],
        nextDue: j['next_due'] == null
            ? null
            : DateTime.tryParse(j['next_due'])?.toLocal(),
      );
}

/// What one person did on the chosen day. Counts, never rates — a rate over
/// one person's single day is noise, and it invites ranking.
class LeadFunnel {
  final int calls;
  final int reached;
  final int counselling;
  final int trialsBooked;
  final int joined;
  final int notesLogged;

  const LeadFunnel({
    required this.calls,
    required this.reached,
    required this.counselling,
    required this.trialsBooked,
    required this.joined,
    required this.notesLogged,
  });

  factory LeadFunnel.fromJson(Map<String, dynamic> j) => LeadFunnel(
        calls: j['calls'] ?? 0,
        reached: j['reached'] ?? 0,
        counselling: j['counselling'] ?? 0,
        trialsBooked: j['trials_booked'] ?? 0,
        joined: j['joined'] ?? 0,
        notesLogged: j['notes_logged'] ?? 0,
      );

  bool get isEmpty =>
      calls == 0 && counselling == 0 && trialsBooked == 0 &&
      joined == 0 && notesLogged == 0;
}

class StaffLeadWork {
  final int? userId;
  final String name;
  final String? role;
  final LeadWorkload carrying;
  final LeadFunnel worked;

  const StaffLeadWork({
    this.userId,
    required this.name,
    this.role,
    required this.carrying,
    required this.worked,
  });

  factory StaffLeadWork.fromJson(Map<String, dynamic> j) => StaffLeadWork(
        userId: j['user_id'],
        name: j['name'] ?? '',
        role: j['role'],
        carrying: LeadWorkload.fromJson(
            (j['carrying'] as Map<String, dynamic>?) ?? {}),
        worked:
            LeadFunnel.fromJson((j['worked'] as Map<String, dynamic>?) ?? {}),
      );

  bool get isUnassignedBucket => userId == null;
}

class LeadWorkReport {
  final String date;
  final String from;
  final String to;
  final int days;

  final List<StaffLeadWork> staff;
  final int totalOpen;
  final int totalUnattended;
  final int totalOverdue;

  const LeadWorkReport({
    required this.date,
    required this.from,
    required this.to,
    required this.days,
    required this.staff,
    required this.totalOpen,
    required this.totalUnattended,
    required this.totalOverdue,
  });

  factory LeadWorkReport.fromJson(Map<String, dynamic> j) => LeadWorkReport(
        date: j['date'] ?? '',
        from: j['from'] ?? '',
        to: j['to'] ?? '',
        days: j['days'] ?? 1,
        staff: ((j['staff'] as List?) ?? [])
            .map((e) => StaffLeadWork.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalOpen: j['total_open'] ?? 0,
        totalUnattended: j['total_unattended'] ?? 0,
        totalOverdue: j['total_overdue'] ?? 0,
      );

  bool get isEmpty => staff.isEmpty;
}
