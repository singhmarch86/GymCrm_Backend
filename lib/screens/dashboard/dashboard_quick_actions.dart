import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/dashboard_action_card.dart';

import '../../features/attendance/attendance_screen.dart';
import '../../features/branch/branch_screen.dart';
import '../../features/classes/classes_screen.dart';
import '../../features/imports/import_screen.dart';
import '../../features/invoices/invoices_screen.dart';
import '../../features/leads/leads_screen.dart';
import '../../features/members/member_screen.dart';
import '../../features/payments/payments_screen.dart';
import '../../features/pos/pos_screen.dart';
import '../../features/personal_training/personal_training_screen.dart';
import '../../features/referrals/referrals_screen.dart';
import '../../features/renewals/renewals_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/retention/at_risk_screen.dart';
import '../../features/staff/staff_screen.dart';
import '../../features/trainers/trainers_screen.dart';
import '../../features/visitors/visitors_screen.dart';
import '../plans_screen.dart';

/// One navigation entry, so the list can be laid out by the grid below rather
/// than each card hard-coding its own position.
class _Action {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget Function() screen;
  final String? badge;

  const _Action({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.screen,
    this.badge,
  });
}

class DashboardQuickActions extends StatelessWidget {
  /// Called when a pushed screen reports that business data changed
  /// (Navigator.pop(context, true)) — see member_screen.dart, plans_screen.dart
  /// and renewals_screen.dart for where that `true` actually gets set.
  /// The Dashboard wires this to its own loadDashboard() (see
  /// dashboard_screen.dart), so this widget never needs to know how the
  /// dashboard refreshes — only that something changed.
  final VoidCallback onDataChanged;

  /// Surfaced as a badge on the Renewals tile so a busy day doesn't require
  /// opening the screen just to check whether anything's due.
  final int renewalsToday;

  /// High-severity churn alerts, badged on the At Risk tile so the number is
  /// visible without opening the screen.
  final int atRiskHigh;

  const DashboardQuickActions({
    super.key,
    required this.onDataChanged,
    this.renewalsToday = 0,
    this.atRiskHigh = 0,
  });

  Future<void> _openAndMaybeRefresh(
    BuildContext context,
    Widget screen,
  ) async {
    final changed = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );

    if (changed == true) {
      onDataChanged();
    }
  }

  List<_Action> get _actions => [
        _Action(
          title: 'Members',
          subtitle: 'Manage all gym members',
          icon: Icons.groups_rounded,
          color: AppColors.primary,
          screen: () => const MembersScreen(),
        ),
        _Action(
          title: 'Leads',
          subtitle: 'Pipeline, follow-ups, analytics',
          icon: Icons.person_add_rounded,
          color: AppColors.warning,
          screen: () => const LeadsScreen(),
        ),
        _Action(
          title: 'Renewals',
          subtitle: 'Track expiring memberships',
          icon: Icons.autorenew_rounded,
          color: AppColors.danger,
          screen: () => const RenewalsScreen(),
          badge: renewalsToday > 0 ? '$renewalsToday today' : null,
        ),
        _Action(
          title: 'At Risk',
          subtitle: 'Members drifting or lapsing',
          icon: Icons.health_and_safety_rounded,
          color: AppColors.danger,
          screen: () => const AtRiskScreen(),
          badge: atRiskHigh > 0 ? '$atRiskHigh high' : null,
        ),
        _Action(
          title: 'Payments',
          subtitle: 'Collections and pending dues',
          icon: Icons.payment_rounded,
          color: AppColors.success,
          screen: () => const PaymentsScreen(),
        ),
        _Action(
          title: 'Shop',
          subtitle: 'Sell products, track stock',
          icon: Icons.storefront_rounded,
          color: AppColors.success,
          screen: () => const PosScreen(),
        ),
        _Action(
          title: 'Invoices',
          subtitle: 'GST invoices and discounts',
          icon: Icons.receipt_long_rounded,
          color: AppColors.primary,
          screen: () => const InvoicesScreen(),
        ),
        _Action(
          title: 'Attendance',
          subtitle: 'Check in members, view history',
          icon: Icons.how_to_reg_rounded,
          color: AppColors.info,
          screen: () => const AttendanceScreen(),
        ),
        _Action(
          title: 'Classes',
          subtitle: 'Schedules, sessions, bookings',
          icon: Icons.self_improvement_rounded,
          color: AppColors.success,
          screen: () => const ClassesScreen(),
        ),
        _Action(
          title: 'Plans',
          subtitle: 'Create & update membership plans',
          icon: Icons.workspace_premium_rounded,
          color: AppColors.primary,
          screen: () => const PlansScreen(),
        ),
        _Action(
          title: 'Reports',
          subtitle: 'Revenue, members, analytics',
          icon: Icons.bar_chart_rounded,
          color: AppColors.info,
          screen: () => const ReportsScreen(),
        ),
        _Action(
          title: 'Staff',
          subtitle: 'Add trainers and manage access',
          icon: Icons.badge_rounded,
          color: AppColors.textSecondary,
          screen: () => const StaffScreen(),
        ),
        _Action(
          title: 'Visitors',
          subtitle: 'Walk-ins, trials, tours',
          icon: Icons.groups_2_rounded,
          color: AppColors.info,
          screen: () => const VisitorsScreen(),
        ),
        _Action(
          title: 'Referrals',
          subtitle: 'Member-to-member referrals',
          icon: Icons.diversity_3_rounded,
          color: AppColors.warning,
          screen: () => const ReferralsScreen(),
        ),
        _Action(
          title: 'Branches',
          subtitle: 'Switch location, chain overview',
          icon: Icons.store_rounded,
          color: AppColors.primary,
          screen: () => const BranchScreen(),
        ),
        _Action(
          title: 'Import data',
          subtitle: 'Bring members and history across',
          icon: Icons.upload_file_rounded,
          color: AppColors.info,
          screen: () => const ImportScreen(),
        ),
        _Action(
          title: 'Trainers',
          subtitle: 'PT roster and specializations',
          icon: Icons.sports_rounded,
          color: AppColors.primary,
          screen: () => const TrainersScreen(),
        ),
        _Action(
          title: 'Personal Training',
          subtitle: 'Packages and 1:1 appointments',
          icon: Icons.fitness_center_rounded,
          color: AppColors.success,
          screen: () => const PersonalTrainingScreen(),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final actions = _actions;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Eight full-width cards stacked vertically is a very long scroll on a
        // desktop window while the horizontal space goes unused. Columns are
        // chosen by available width, matching the 700px breakpoint the stats
        // grid already uses so the two sections stay visually in step.
        final int columns = constraints.maxWidth > 1100
            ? 4
            : constraints.maxWidth > 700
                ? 2
                : 1;

        const gap = 16.0;
        final cardWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: actions
              .map(
                (a) => SizedBox(
                  width: cardWidth,
                  child: DashboardActionCard(
                    title: a.title,
                    subtitle: a.subtitle,
                    icon: a.icon,
                    color: a.color,
                    badge: a.badge,
                    onTap: () => _openAndMaybeRefresh(context, a.screen()),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}
