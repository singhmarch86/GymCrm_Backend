import 'package:flutter/material.dart';

import '../features/analytics/analytics_screen.dart';
import '../features/leads/leads_screen.dart';
import '../features/members/member_screen.dart';
import '../features/retention/at_risk_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../theme/app_colors.dart';
import 'more_section.dart';

/// The persistent section shell (FR-14).
///
/// Sections are *places*, not destinations you push and pop. Before this, every
/// one of the nineteen dashboard tiles pushed a screen the user had to back out
/// of — dozens of times a day at a front desk — and every trip back lost the
/// scroll position they had worked down to.
///
/// The screens inside are unchanged. This is a container, deliberately: a
/// second implementation of each screen for "tab mode" would be two things to
/// keep in sync and one of them would always be broken.
class AppShell extends StatefulWidget {
  /// Which section to open on. Defaults to Today.
  final int initialIndex;

  const AppShell({super.key, this.initialIndex = 0});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index = widget.initialIndex;

  /// Built once, kept alive by the IndexedStack below.
  ///
  /// This is what makes rule 3 true: a receptionist who scrolls to the bottom
  /// of At Risk, takes a payment, and comes back must find themselves where
  /// they left off. Rebuilding on every switch would reset scroll, filters and
  /// sub-tab, which is a worse tool than the one they had.
  late final List<Widget> _sections = [
    // Today drops the tile grid — it lives in More now, so what remains is the
    // numbers that actually change daily (FR-14 §5).
    const DashboardScreen(showQuickActions: false),
    const MembersScreen(),
    // Opens on the board, not the list: the board answers "where is the funnel
    // blocked", which is the question an owner actually has.
    const LeadsScreen(initialTab: LeadsScreen.boardTab),
    const AtRiskScreen(),
    // Every number the product computes, in one place (FR-15). It earns a tab
    // because visibility is the entire point — scattered across four screens,
    // the depth that was already built read as absent.
    const AnalyticsScreen(),
    const MoreSection(),
  ];

  static const _destinations = [
    (Icons.dashboard_rounded, Icons.dashboard_outlined, 'Today'),
    (Icons.groups_rounded, Icons.groups_outlined, 'Members'),
    (Icons.person_add_rounded, Icons.person_add_alt_outlined, 'Leads'),
    (
      Icons.health_and_safety_rounded,
      Icons.health_and_safety_outlined,
      'At Risk',
    ),
    (Icons.insights_rounded, Icons.insights_outlined, 'Analytics'),
    (Icons.apps_rounded, Icons.apps_outlined, 'More'),
  ];

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // 900 matches Breakpoints.tablet, so the shell changes shape at the same
    // width the screens inside it already reflow at.
    final wide = width >= 900;

    final body = IndexedStack(index: _index, children: _sections);

    if (wide) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: _select,
              labelType: NavigationRailLabelType.all,
              backgroundColor: Colors.white,
              indicatorColor: AppColors.primary.withValues(alpha: 0.12),
              selectedIconTheme: const IconThemeData(color: AppColors.primary),
              selectedLabelTextStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
              unselectedLabelTextStyle: TextStyle(
                fontSize: 11.5,
                color: Colors.grey.shade600,
              ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.$2),
                    selectedIcon: Icon(d.$1),
                    label: Text(d.$3),
                  ),
              ],
            ),
            const VerticalDivider(width: 1, color: AppColors.border),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        backgroundColor: Colors.white,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        // Tighter than the Material default, which wastes a phone row on
        // padding alone (FR-14 §5).
        height: 62,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.$2, size: 22),
              selectedIcon: Icon(d.$1, size: 22, color: AppColors.primary),
              label: d.$3,
            ),
        ],
      ),
    );
  }
}
