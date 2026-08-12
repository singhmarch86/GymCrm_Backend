/// The collections queue (FR-19 §3) — money owed and not collected.
///
/// Grouped by member, never by collector. A collections list with staff names
/// and rupee totals against them is one design decision away from a sales
/// leaderboard, which FR-13 §1 exists to prevent.
library;

class CollectionItem {
  final int paymentId;
  final int memberId;
  final String member;
  final String phone;

  final int amountInPaise;
  final DateTime? dueDate;

  /// Negative means not yet due. Null when the due carries no date at all —
  /// its own kind of problem, and shown as such rather than assumed to be
  /// today.
  final int? daysOverdue;

  /// Everything this member owes, across every outstanding due.
  final int memberTotalInPaise;

  final DateTime? lastContactAt;
  final String? lastContactBy;
  final String? lastContactNote;
  final bool? lastReached;

  final DateTime? promisedOn;

  /// The membership itself has lapsed. Changes the conversation entirely, and
  /// would otherwise be a nasty surprise halfway through the call.
  final bool memberInactive;

  const CollectionItem({
    required this.paymentId,
    required this.memberId,
    required this.member,
    required this.phone,
    required this.amountInPaise,
    this.dueDate,
    this.daysOverdue,
    required this.memberTotalInPaise,
    this.lastContactAt,
    this.lastContactBy,
    this.lastContactNote,
    this.lastReached,
    this.promisedOn,
    required this.memberInactive,
  });

  factory CollectionItem.fromJson(Map<String, dynamic> j) => CollectionItem(
        paymentId: j['payment_id'] ?? 0,
        memberId: j['member_id'] ?? 0,
        member: j['member'] ?? '',
        phone: j['phone'] ?? '',
        amountInPaise: j['amount_in_paise'] ?? 0,
        dueDate: _date(j['due_date']),
        daysOverdue: j['days_overdue'],
        memberTotalInPaise: j['member_total_in_paise'] ?? 0,
        lastContactAt: _date(j['last_contact_at']),
        lastContactBy: j['last_contact_by'],
        lastContactNote: j['last_contact_note'],
        lastReached: j['last_reached'],
        promisedOn: _date(j['promised_on']),
        memberInactive: j['member_inactive'] ?? false,
      );

  /// True when this due is not the whole story for this member.
  bool get owesMore => memberTotalInPaise > amountInPaise;

  static DateTime? _date(dynamic v) {
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v)?.toLocal();
  }
}

class CollectionGroup {
  final String key;
  final String label;
  final String note;
  final String severity;
  final List<CollectionItem> items;
  final int totalInPaise;

  const CollectionGroup({
    required this.key,
    required this.label,
    required this.note,
    required this.severity,
    required this.items,
    required this.totalInPaise,
  });

  factory CollectionGroup.fromJson(Map<String, dynamic> j) => CollectionGroup(
        key: j['key'] ?? '',
        label: j['label'] ?? '',
        note: j['note'] ?? '',
        severity: j['severity'] ?? 'normal',
        items: ((j['items'] as List?) ?? [])
            .map((e) => CollectionItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalInPaise: j['total_in_paise'] ?? 0,
      );
}

class CollectionQueue {
  final List<CollectionGroup> groups;
  final int totalCount;
  final int totalInPaise;
  final int unchasedCount;
  final int membersInvolved;

  /// What a due-date window is hiding. Filtering a debt list is not like
  /// filtering a report — the oldest debt is the worst debt — so the amount
  /// left out is returned and shown rather than quietly dropped.
  final int outsideCount;
  final int outsideInPaise;

  const CollectionQueue({
    required this.groups,
    required this.totalCount,
    required this.totalInPaise,
    required this.unchasedCount,
    required this.membersInvolved,
    this.outsideCount = 0,
    this.outsideInPaise = 0,
  });

  factory CollectionQueue.fromJson(Map<String, dynamic> j) => CollectionQueue(
        groups: ((j['groups'] as List?) ?? [])
            .map((e) => CollectionGroup.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalCount: j['total_count'] ?? 0,
        totalInPaise: j['total_in_paise'] ?? 0,
        unchasedCount: j['unchased_count'] ?? 0,
        membersInvolved: j['members_involved'] ?? 0,
        outsideCount: j['outside_count'] ?? 0,
        outsideInPaise: j['outside_in_paise'] ?? 0,
      );

  bool get isClear => totalCount == 0;
}
