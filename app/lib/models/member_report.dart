class MemberGrowthPoint {
  final String month;
  final int joined;
  final int expired;

  MemberGrowthPoint({
    required this.month,
    required this.joined,
    required this.expired,
  });

  factory MemberGrowthPoint.fromJson(Map<String, dynamic> j) =>
      MemberGrowthPoint(
        month: j['month'] ?? '',
        joined: j['joined'] ?? 0,
        expired: j['expired'] ?? 0,
      );
}

class MemberReport {
  final int total;
  final int active;
  final int expired;
  final int newThisMonth;
  final double growthPct;
  final List<MemberGrowthPoint> growth;

  MemberReport({
    required this.total,
    required this.active,
    required this.expired,
    required this.newThisMonth,
    required this.growthPct,
    required this.growth,
  });

  factory MemberReport.fromJson(Map<String, dynamic> j) => MemberReport(
    total: j['total'] ?? 0,
    active: j['active'] ?? 0,
    expired: j['expired'] ?? 0,
    newThisMonth: j['new_this_month'] ?? 0,
    growthPct: (j['growth_pct'] ?? 0).toDouble(),
    growth: (j['growth'] as List? ?? [])
        .map((e) => MemberGrowthPoint.fromJson(e))
        .toList(),
  );
}
