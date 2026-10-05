class DashboardResponse {
  final int totalMembers;
  final int activeMembers;
  final int expiredMembers;

  final int expiring7Days;
  final int expiring30Days;

  final int renewalsToday;
  final int renewalsThisMonth;

  final int revenueThisMonth;

  final int attendanceToday;

  final int inactive7Days;
  final int inactive14Days;
  final int inactive30Days;

  DashboardResponse({
    required this.totalMembers,
    required this.activeMembers,
    required this.expiredMembers,
    required this.expiring7Days,
    required this.expiring30Days,
    required this.renewalsToday,
    required this.renewalsThisMonth,
    required this.revenueThisMonth,
    required this.attendanceToday,
    required this.inactive7Days,
    required this.inactive14Days,
    required this.inactive30Days,
  });

  factory DashboardResponse.fromJson(Map<String, dynamic> json) {
    return DashboardResponse(
      totalMembers: json['total_members'] ?? 0,
      activeMembers: json['active_members'] ?? 0,
      expiredMembers: json['expired_members'] ?? 0,

      expiring7Days: json['expiring_7_days'] ?? 0,
      expiring30Days: json['expiring_30_days'] ?? 0,

      renewalsToday: json['renewals_today'] ?? 0,
      renewalsThisMonth: json['renewals_this_month'] ?? 0,

      revenueThisMonth: json['revenue_this_month'] ?? 0,

      attendanceToday: json['attendance_today'] ?? 0,

      inactive7Days: json['inactive_7_days'] ?? 0,
      inactive14Days: json['inactive_14_days'] ?? 0,
      inactive30Days: json['inactive_30_days'] ?? 0,
    );
  }
}
