import 'package:flutter/material.dart';

import '../screens/dashboard/dashboard_quick_actions.dart';
import '../theme/app_colors.dart';

/// Everything that does not earn a permanent tab (FR-14 §7).
///
/// The grouped map of the whole product, one tap from anywhere. Nothing that
/// was reachable before this change is unreachable now — a navigation rework
/// that quietly drops a feature is how a gym discovers three weeks in that the
/// thing they bought it for is gone.
class MoreSection extends StatelessWidget {
  const MoreSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Everything else'),
        // No back button: this is a section, not a pushed screen, and an arrow
        // that pops the shell would strand the user on the login screen.
        automaticallyImplyLeading: false,
        toolbarHeight: 48,
      ),
      body: SingleChildScrollView(
        // Tighter than the old dashboard's padding — the rail or bottom bar
        // already says where the user is, so the page does not need to.
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        child: DashboardQuickActions(
          // Nothing here changes the numbers on Today, and the shell keeps
          // every section alive anyway, so a refresh callback would be a lie.
          // Today reloads itself when it is next shown.
          onDataChanged: () {},
        ),
      ),
    );
  }
}
