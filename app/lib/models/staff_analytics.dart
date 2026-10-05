/// Staff work analytics (FR-22).
///
/// The model deliberately offers no way to rank people. There is no score and
/// no sortable output field; the only comparison available is
/// [PersonTrend.previousCount], which is the same person in the previous
/// period. A list sorted by output is a ranking whatever the heading says
/// (FR-13 §1), so the server orders [StaffAnalytics.people] by name and the
/// screen keeps that order.
library;

class TrendPoint {
  final String key;
  final String label;
  final int count;
  final int amountInPaise;

  /// Nothing recorded at all. An explicit zero, not a missing column: a gap in
  /// a series reads as absent data, and a day the gym logged nothing is a fact
  /// worth seeing.
  final bool quiet;

  const TrendPoint({
    required this.key,
    required this.label,
    required this.count,
    required this.amountInPaise,
    required this.quiet,
  });

  factory TrendPoint.fromJson(Map<String, dynamic> j) => TrendPoint(
    key: j['key'] ?? '',
    label: j['label'] ?? '',
    count: j['count'] ?? 0,
    amountInPaise: j['amount_in_paise'] ?? 0,
    quiet: j['quiet'] ?? false,
  );
}

class CategoryTotal {
  final String category;
  final String label;
  final int count;
  final int amountInPaise;
  final int sharePct;

  const CategoryTotal({
    required this.category,
    required this.label,
    required this.count,
    required this.amountInPaise,
    required this.sharePct,
  });

  factory CategoryTotal.fromJson(Map<String, dynamic> j) => CategoryTotal(
    category: j['category'] ?? '',
    label: j['label'] ?? '',
    count: j['count'] ?? 0,
    amountInPaise: j['amount_in_paise'] ?? 0,
    sharePct: j['share_pct'] ?? 0,
  );
}

class PersonTrend {
  final int? userId;
  final String name;
  final String role;

  final int count;
  final int amountInPaise;

  /// The same person, in the equal-length span immediately before this one.
  final int previousCount;

  /// Null when there is no previous period. A new joiner is not down 100%.
  final int? changePct;

  const PersonTrend({
    this.userId,
    required this.name,
    required this.role,
    required this.count,
    required this.amountInPaise,
    required this.previousCount,
    this.changePct,
  });

  factory PersonTrend.fromJson(Map<String, dynamic> j) => PersonTrend(
    userId: j['user_id'],
    name: j['name'] ?? '',
    role: j['role'] ?? '',
    count: j['count'] ?? 0,
    amountInPaise: j['amount_in_paise'] ?? 0,
    previousCount: j['previous_count'] ?? 0,
    changePct: j['change_pct'],
  );
}

class StaffAnalytics {
  final String from;
  final String to;
  final int days;

  /// `day` or `week`.
  final String trendUnit;
  final List<TrendPoint> trend;

  final List<CategoryTotal> categories;

  /// Ordered by name by the server. Never re-sort this.
  final List<PersonTrend> people;

  final int totalCount;
  final int totalAmountInPaise;

  final int unattributedCount;
  final int unattributedPct;

  final int quietDays;

  const StaffAnalytics({
    required this.from,
    required this.to,
    required this.days,
    required this.trendUnit,
    required this.trend,
    required this.categories,
    required this.people,
    required this.totalCount,
    required this.totalAmountInPaise,
    required this.unattributedCount,
    required this.unattributedPct,
    required this.quietDays,
  });

  bool get isEmpty => totalCount == 0;

  /// The busiest column, for scaling the rhythm chart.
  int get peakCount {
    var peak = 0;
    for (final t in trend) {
      if (t.count > peak) peak = t.count;
    }
    return peak;
  }

  factory StaffAnalytics.fromJson(Map<String, dynamic> j) => StaffAnalytics(
    from: j['from'] ?? '',
    to: j['to'] ?? '',
    days: j['days'] ?? 0,
    trendUnit: j['trend_unit'] ?? 'day',
    trend: ((j['trend'] as List?) ?? [])
        .map((e) => TrendPoint.fromJson(e as Map<String, dynamic>))
        .toList(),
    categories: ((j['categories'] as List?) ?? [])
        .map((e) => CategoryTotal.fromJson(e as Map<String, dynamic>))
        .toList(),
    people: ((j['people'] as List?) ?? [])
        .map((e) => PersonTrend.fromJson(e as Map<String, dynamic>))
        .toList(),
    totalCount: j['total_count'] ?? 0,
    totalAmountInPaise: j['total_amount_in_paise'] ?? 0,
    unattributedCount: j['unattributed_count'] ?? 0,
    unattributedPct: j['unattributed_pct'] ?? 0,
    quietDays: j['quiet_days'] ?? 0,
  );
}
