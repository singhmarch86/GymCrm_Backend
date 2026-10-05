/// Money leakage (FR-21) — value the gym handed over without billing it.
///
/// The collections queue answers "who owes us money we billed". This answers
/// the harder one: "what did we give away and never bill at all". None of it
/// appears in a debtors list, because nobody ever wrote the debt down.
///
/// Every row is a finding, never an accusation. A session past a package's
/// limit may be goodwill somebody approved; a visit after expiry may be a cash
/// renewal nobody keyed in.
library;

class LeakItem {
  final String kind;

  final int memberId;
  final String member;
  final String phone;

  final int? trainerId;
  final String? trainer;

  final String detail;

  /// Zero where the finding cannot be valued honestly. A drifted counter costs
  /// nothing by itself, and inventing a figure would make the total
  /// meaningless.
  final int valueInPaise;

  /// How the figure was reached, shown beside it. A number nobody can
  /// reconstruct is a number nobody will act on.
  final String basis;

  final int count;
  final DateTime? since;
  final int? packageId;

  const LeakItem({
    required this.kind,
    required this.memberId,
    required this.member,
    required this.phone,
    this.trainerId,
    this.trainer,
    required this.detail,
    required this.valueInPaise,
    required this.basis,
    required this.count,
    this.since,
    this.packageId,
  });

  factory LeakItem.fromJson(Map<String, dynamic> j) => LeakItem(
    kind: j['kind'] ?? '',
    memberId: j['member_id'] ?? 0,
    member: j['member'] ?? '',
    phone: j['phone'] ?? '',
    trainerId: j['trainer_id'],
    trainer: j['trainer'],
    detail: j['detail'] ?? '',
    valueInPaise: j['value_in_paise'] ?? 0,
    basis: j['basis'] ?? '',
    count: j['count'] ?? 0,
    since: _date(j['since']),
    packageId: j['package_id'],
  );

  static DateTime? _date(dynamic v) {
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v)?.toLocal();
  }
}

class LeakGroup {
  final String kind;
  final String label;
  final String note;
  final String severity;
  final List<LeakItem> items;
  final int valueInPaise;

  const LeakGroup({
    required this.kind,
    required this.label,
    required this.note,
    required this.severity,
    required this.items,
    required this.valueInPaise,
  });

  factory LeakGroup.fromJson(Map<String, dynamic> j) => LeakGroup(
    kind: j['kind'] ?? '',
    label: j['label'] ?? '',
    note: j['note'] ?? '',
    severity: j['severity'] ?? 'normal',
    items: ((j['items'] as List?) ?? [])
        .map((e) => LeakItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    valueInPaise: j['value_in_paise'] ?? 0,
  );
}

class LeakageReport {
  final List<LeakGroup> groups;
  final int totalCount;

  /// Only what could be valued honestly. This is the FLOOR of what leaked,
  /// never the whole of it, and the screen says so.
  final int valuedInPaise;

  final int unvaluedCount;

  const LeakageReport({
    required this.groups,
    required this.totalCount,
    required this.valuedInPaise,
    required this.unvaluedCount,
  });

  bool get isClear => totalCount == 0;

  factory LeakageReport.fromJson(Map<String, dynamic> j) => LeakageReport(
    groups: ((j['groups'] as List?) ?? [])
        .map((e) => LeakGroup.fromJson(e as Map<String, dynamic>))
        .toList(),
    totalCount: j['total_count'] ?? 0,
    valuedInPaise: j['valued_in_paise'] ?? 0,
    unvaluedCount: j['unvalued_count'] ?? 0,
  );
}
