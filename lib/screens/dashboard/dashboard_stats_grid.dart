import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/dashboard_kpi_card.dart';

class DashboardStatsGrid extends StatelessWidget {
  final int totalMembers;
  final int activeMembers;
  final int expiring7Days;
  final int revenueThisMonthPaise;

  const DashboardStatsGrid({
    super.key,
    required this.totalMembers,
    required this.activeMembers,
    required this.expiring7Days,
    required this.revenueThisMonthPaise,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Mobile: 2 columns
        // Tablet/Desktop: 4 columns
        final bool isWide = constraints.maxWidth > 700;

        if (isWide) {
          return Row(
            children: [
              Expanded(child: _membersCard()),
              const SizedBox(width: 16),
              Expanded(child: _activeCard()),
              const SizedBox(width: 16),
              Expanded(child: _expiringCard()),
              const SizedBox(width: 16),
              Expanded(child: _revenueCard()),
            ],
          );
        }

        return Column(
          children: [
            Row(
              children: [
                Expanded(child: _membersCard()),
                const SizedBox(width: 16),
                Expanded(child: _activeCard()),
              ],
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(child: _expiringCard()),
                const SizedBox(width: 16),
                Expanded(child: _revenueCard()),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _membersCard() {
    return DashboardKpiCard(
      title: 'Members',
      value: totalMembers.toString(),
      icon: Icons.groups_rounded,
      color: AppColors.primary,
      subtitle: 'Total registered',
    );
  }

  Widget _activeCard() {
    return DashboardKpiCard(
      title: 'Active',
      value: activeMembers.toString(),
      icon: Icons.check_circle_outline_rounded,
      color: AppColors.success,
      subtitle: 'Currently active',
    );
  }

  Widget _expiringCard() {
    return DashboardKpiCard(
      title: 'Expiring',
      value: expiring7Days.toString(),
      icon: Icons.schedule_rounded,
      color: AppColors.warning,
      subtitle: 'Due in 7 days',
    );
  }

  Widget _revenueCard() {
    return DashboardKpiCard(
      title: 'Revenue',
      value: '₹${(revenueThisMonthPaise / 100).toStringAsFixed(0)}',
      icon: Icons.currency_rupee_rounded,
      color: AppColors.info,
      subtitle: 'This month',
    );
  }
}
