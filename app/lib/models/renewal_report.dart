class RenewalTrendPoint {
  final String month;
  final int count;

  RenewalTrendPoint({required this.month, required this.count});

  factory RenewalTrendPoint.fromJson(Map<String, dynamic> j) =>
      RenewalTrendPoint(month: j['month'] ?? '', count: j['count'] ?? 0);
}

class RenewalReport {
  final int dueToday;
  final int completedThisMonth;
  final double successRate;
  final List<RenewalTrendPoint> trend;

  RenewalReport({
    required this.dueToday,
    required this.completedThisMonth,
    required this.successRate,
    required this.trend,
  });

  factory RenewalReport.fromJson(Map<String, dynamic> j) => RenewalReport(
    dueToday: j['due_today'] ?? 0,
    completedThisMonth: j['completed_this_month'] ?? 0,
    successRate: (j['success_rate'] ?? 0).toDouble(),
    trend: (j['trend'] as List? ?? [])
        .map((e) => RenewalTrendPoint.fromJson(e))
        .toList(),
  );
}
