import 'package:flutter/material.dart';

import '../../widgets/app_spacing.dart';
import '../../widgets/dashboard_header.dart';
import '../../widgets/dashboard_renewals_card.dart';
import '../../widgets/dashboard_revenue_card.dart';
import '../../widgets/dashboard_section_title.dart';

import 'dashboard_insight_banner.dart';
import 'dashboard_quick_actions.dart';
import 'dashboard_recent_activity.dart';
import 'dashboard_stats_grid.dart';

class DashboardBody extends StatelessWidget {
  final String userName;
  final String role;

  final int totalMembers;
  final int activeMembers;
  final int expiredMembers;
  final int expiring7Days;
  final int expiring30Days;
  final int inactive7Days;
  final int inactive14Days;
  final int inactive30Days;
  final int renewalsToday;
  final int atRiskHigh;

  // Revenue stats — owned by DashboardScreen.loadDashboard() so a single
  // refresh updates every number on the screen simultaneously.
  final int todayRevenuePaise;
  final int monthRevenuePaise;
  final int pendingPayments;
  final int collectedCount;

  final VoidCallback onLogout;
  final VoidCallback onDataChanged;

  const DashboardBody({
    super.key,
    required this.userName,
    required this.role,
    required this.totalMembers,
    required this.activeMembers,
    required this.expiredMembers,
    required this.expiring7Days,
    required this.expiring30Days,
    required this.inactive7Days,
    required this.inactive14Days,
    required this.inactive30Days,
    required this.renewalsToday,
    required this.atRiskHigh,
    required this.todayRevenuePaise,
    required this.monthRevenuePaise,
    required this.pendingPayments,
    required this.collectedCount,
    required this.onLogout,
    required this.onDataChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Renewals and Revenue are both compact 3-stat cards; side by side they
        // read as one "money and expiry" band instead of two lonely full-width
        // strips. Below the same 700px breakpoint the rest of the dashboard
        // uses, they stack.
        final bool isWide = constraints.maxWidth > 700;

        return Center(
          // Past ~1400px the content stops gaining anything from more width —
          // lines of text get uncomfortably long and the eye has to travel.
          // Cap it and centre, rather than stretching to fill an ultrawide.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: _content(isWide),
          ),
        );
      },
    );
  }

  Widget _content(bool isWide) {
    return ListView(
      physics:
      const AlwaysScrollableScrollPhysics(),
      padding: AppSpacing.screenPadding,
      children: [

        DashboardHeader(
          userName: userName,
          role: role,
          onLogout: onLogout,
        ),

        AppSpacing.gapXl,

        DashboardInsightBanner(
          inactive14Days: inactive14Days,
          inactive30Days: inactive30Days,
          expiring7Days: expiring7Days,
        ),

        const DashboardSectionTitle(
          title: "Today's Overview",
        ),

        AppSpacing.gapLg,

        DashboardStatsGrid(
          totalMembers: totalMembers,
          activeMembers: activeMembers,
          expiring7Days: expiring7Days,
          revenueThisMonthPaise: monthRevenuePaise,
        ),

        AppSpacing.gapLg,

        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DashboardRenewalsCard(onDataChanged: onDataChanged),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DashboardRevenueCard(
                  todayRevenuePaise: todayRevenuePaise,
                  monthRevenuePaise: monthRevenuePaise,
                  pendingPayments: pendingPayments,
                  collectedCount: collectedCount,
                  onDataChanged: onDataChanged,
                ),
              ),
            ],
          )
        else ...[
          DashboardRenewalsCard(onDataChanged: onDataChanged),
          AppSpacing.gapLg,
          DashboardRevenueCard(
            todayRevenuePaise: todayRevenuePaise,
            monthRevenuePaise: monthRevenuePaise,
            pendingPayments: pendingPayments,
            collectedCount: collectedCount,
            onDataChanged: onDataChanged,
          ),
        ],

        AppSpacing.gapXxl,

        const DashboardSectionTitle(
          title: "Quick Actions",
        ),

        AppSpacing.gapLg,

        DashboardQuickActions(
          onDataChanged: onDataChanged,
          renewalsToday: renewalsToday,
          atRiskHigh: atRiskHigh,
        ),

        AppSpacing.gapXxl,

        const DashboardSectionTitle(
          title: "Recent Activity",
        ),

        AppSpacing.gapLg,

        const DashboardRecentActivity(),

        AppSpacing.gapXxl,
      ],
    );
  }
}