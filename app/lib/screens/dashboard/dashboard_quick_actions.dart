import 'package:flutter/material.dart';

import '../../services/entitlements_service.dart';
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
import '../../features/money/leakage_screen.dart';
import '../../features/payouts/payouts_screen.dart';
import '../../features/staffwork/staff_work_screen.dart';
import '../../features/trainers/trainers_screen.dart';
import '../../features/visitors/visitors_screen.dart';
import '../plans_screen.dart';

/// One group of navigation entries, rendered under its own heading.
///
/// Density is the other half of the fix: the secondary groups use a compact
/// tile so four rows of them occupy the space one row of big cards used to,
/// which is what lets the whole map of the product fit on one screen at desk
/// width instead of scrolling past the fold.
class _ActionSection extends StatelessWidget {
  final String heading;
  final String blurb;
  final List<_Action> actions;
  final bool prominent;
  final double width;
  final double topPadding;
  final void Function(_Action) onTap;

  const _ActionSection({
    required this.heading,
    required this.blurb,
    required this.actions,
    required this.prominent,
    required this.width,
    required this.topPadding,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();

    // Prominent cards need room to breathe; compact tiles are sized so a
    // phone still gets two per row and a desk screen gets six.
    final int columns = prominent
        ? (width > 1100 ? 3 : (width > 700 ? 2 : 1))
        : (width > 1100 ? 6 : (width > 700 ? 4 : 2));

    const gap = 12.0;
    final tileWidth = (width - gap * (columns - 1)) / columns;

    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  heading,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  blurb,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: gap,
            runSpacing: gap,
            children: actions
                .map(
                  (a) => SizedBox(
                    width: tileWidth,
                    child: prominent
                        ? DashboardActionCard(
                            title: a.title,
                            subtitle: a.subtitle,
                            icon: a.icon,
                            color: a.color,
                            badge: a.badge,
                            onTap: () => onTap(a),
                          )
                        : _CompactTile(action: a, onTap: () => onTap(a)),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

/// A secondary destination: icon, label, optional badge. No subtitle — at this
/// size the subtitle was the thing making the old grid unreadable, because
/// nineteen two-line descriptions is a wall of text nobody reads twice.
class _CompactTile extends StatelessWidget {
  final _Action action;
  final VoidCallback onTap;

  const _CompactTile({required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: action.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(action.icon, size: 18, color: action.color),
                  ),
                  if (action.badge != null)
                    Positioned(
                      right: -6,
                      top: -5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          action.badge!,
                          style: const TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                action.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One navigation entry, so the list can be laid out by the grid below rather
/// than each card hard-coding its own position.
class _Action {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget Function() screen;
  final String? badge;

  /// Which pricing-tier feature this tile needs, if any. Null means
  /// available on every plan — either genuinely core, or a screen this
  /// app hasn't been taught to gate yet (see EntitlementsService's own
  /// "not here yet" list: Reports, Staff, Leads).
  final Feature? feature;

  const _Action({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.screen,
    this.badge,
    this.feature,
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

  Future<void> _openAndMaybeRefresh(BuildContext context, Widget screen) async {
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
      feature: Feature.retentionSignals,
    ),
    _Action(
      title: 'Payments',
      subtitle: 'Collections and pending dues',
      icon: Icons.payment_rounded,
      color: AppColors.success,
      screen: () => const PaymentsScreen(),
    ),
    _Action(
      title: 'Money leaks',
      subtitle: 'Given away, never billed',
      icon: Icons.water_damage_rounded,
      color: AppColors.danger,
      screen: () => const LeakageScreen(),
      feature: Feature.moneyLeaks,
    ),
    _Action(
      title: 'Trainer pay',
      subtitle: 'Salary, commission, sessions',
      icon: Icons.account_balance_wallet_rounded,
      color: AppColors.warning,
      screen: () => const PayoutsScreen(),
      feature: Feature.advancedPayouts,
    ),
    _Action(
      title: 'Staff work',
      subtitle: 'What each person did today',
      icon: Icons.badge_rounded,
      color: AppColors.info,
      screen: () => const StaffWorkScreen(),
      feature: Feature.staffWork,
    ),
    _Action(
      title: 'Shop',
      subtitle: 'Sell products, track stock',
      icon: Icons.storefront_rounded,
      color: AppColors.success,
      screen: () => const PosScreen(),
      feature: Feature.shopPos,
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
      feature: Feature.classes,
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
      // Not gated: MyBranches/Switch (the screen's core, every gym's own
      // branch context) stay available on every plan server-side too — only
      // adding a second location, transfers, and chain-wide views are
      // Premium-gated, inside the screen itself.
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
      // Gated on the same feature as PT feedback, not its own: tapping a
      // trainer here opens TrainerDetailScreen, which is built entirely
      // around PtReportService — a screen with nothing to show below
      // Medium isn't worth reaching.
      feature: Feature.trainerFeedback,
    ),
    _Action(
      title: 'Personal Training',
      subtitle: 'Packages and 1:1 appointments',
      icon: Icons.fitness_center_rounded,
      color: AppColors.success,
      screen: () => const PersonalTrainingScreen(),
      feature: Feature.ptPackages,
    ),
  ];

  /// The information architecture, in one place.
  ///
  /// Nineteen identical tiles in one flat grid meant everything shouted at the
  /// same volume, so nothing did — a receptionist looking for Attendance had to
  /// read all nineteen labels every time. Grouping is what makes a list this
  /// long navigable: you skip to a heading first and read four labels, not
  /// nineteen.
  ///
  /// The order is the working day. What the desk touches hourly comes first;
  /// what gets configured once a year comes last. Titles are matched against
  /// [_actions] so this stays a single, readable statement of the hierarchy
  /// rather than a `group:` field repeated nineteen times.
  static const List<(String, String, List<String>)> _groups = [
    (
      'At the desk',
      'What the front desk touches all day',
      ['Members', 'Attendance', 'Renewals', 'At Risk', 'Payments', 'Shop'],
    ),
    (
      'Growing the gym',
      'Enquiries, walk-ins and word of mouth',
      ['Leads', 'Visitors', 'Referrals'],
    ),
    (
      'Training',
      'Classes, trainers and personal training',
      ['Classes', 'Trainers', 'Personal Training'],
    ),
    (
      'Money and oversight',
      'Billing, reporting, and who did what',
      ['Invoices', 'Money leaks', 'Trainer pay', 'Reports', 'Staff work'],
    ),
    (
      'Setup',
      'Configured once, then left alone',
      ['Plans', 'Staff', 'Branches', 'Import data'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final byTitle = {
      for (final a in _actions)
        if (a.feature == null || EntitlementsService.has(a.feature!))
          a.title: a,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (index, group) in _groups.indexed)
              _ActionSection(
                width: width,
                heading: group.$1,
                blurb: group.$2,
                onTap: (a) => _openAndMaybeRefresh(context, a.screen()),
                // Only the first group gets the large cards. A hierarchy where
                // everything is emphasised is not a hierarchy; the desk work
                // earns the space because it is opened dozens of times a day.
                prominent: index == 0,
                actions: group.$3
                    .map((t) => byTitle[t])
                    .whereType<_Action>()
                    .toList(),
                topPadding: index == 0 ? 0.0 : 22.0,
              ),
          ],
        );
      },
    );
  }
}
