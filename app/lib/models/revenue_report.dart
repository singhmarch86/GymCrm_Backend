class RevenueTrendPoint {
  final String month;
  final int revenueInPaise;
  final double revenueInRupees;

  RevenueTrendPoint({
    required this.month,
    required this.revenueInPaise,
    required this.revenueInRupees,
  });

  factory RevenueTrendPoint.fromJson(Map<String, dynamic> j) =>
      RevenueTrendPoint(
        month: j['month'] ?? '',
        revenueInPaise: j['revenue_in_paise'] ?? 0,
        revenueInRupees: (j['revenue_in_rupees'] ?? 0).toDouble(),
      );
}

class RevenueReport {
  final double todayInRupees;
  final double yesterdayInRupees;
  final double weekInRupees;
  final double monthInRupees;
  final double lastMonthInRupees;
  final List<RevenueTrendPoint> trend;

  RevenueReport({
    required this.todayInRupees,
    required this.yesterdayInRupees,
    required this.weekInRupees,
    required this.monthInRupees,
    required this.lastMonthInRupees,
    required this.trend,
  });

  factory RevenueReport.fromJson(Map<String, dynamic> j) => RevenueReport(
    todayInRupees: (j['today_in_rupees'] ?? 0).toDouble(),
    yesterdayInRupees: (j['yesterday_in_rupees'] ?? 0).toDouble(),
    weekInRupees: (j['week_in_rupees'] ?? 0).toDouble(),
    monthInRupees: (j['month_in_rupees'] ?? 0).toDouble(),
    lastMonthInRupees: (j['last_month_in_rupees'] ?? 0).toDouble(),
    trend: (j['trend'] as List? ?? [])
        .map((e) => RevenueTrendPoint.fromJson(e))
        .toList(),
  );
}
