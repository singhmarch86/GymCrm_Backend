class PlanStat {
  final int planId;
  final String planName;
  final int activeMembers;
  final double revenueInRupees;
  final int countSold;

  PlanStat({
    required this.planId,
    required this.planName,
    required this.activeMembers,
    required this.revenueInRupees,
    required this.countSold,
  });

  factory PlanStat.fromJson(Map<String, dynamic> j) => PlanStat(
    planId: j['plan_id'] ?? 0,
    planName: j['plan_name'] ?? '',
    activeMembers: j['active_members'] ?? 0,
    revenueInRupees: (j['revenue_in_rupees'] ?? 0).toDouble(),
    countSold: j['count_sold'] ?? 0,
  );
}

class PlanReport {
  final List<PlanStat> plans;

  PlanReport({required this.plans});

  factory PlanReport.fromJson(Map<String, dynamic> j) => PlanReport(
    plans: (j['plans'] as List? ?? [])
        .map((e) => PlanStat.fromJson(e))
        .toList(),
  );
}
