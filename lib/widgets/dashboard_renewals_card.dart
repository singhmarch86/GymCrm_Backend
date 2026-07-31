import 'package:flutter/material.dart';

import '../../features/renewals/renewals_screen.dart';
import '../../services/renewal_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/dashboard_card_stat.dart';

/// Dashboard summary card for renewals, matching the PRD mock:
///   Renewals
///   12 Due Today | 28 Due This Week | 3 Overdue
/// Tapping anywhere on the card opens the full Renewals screen.
///
/// Counts are derived client-side from GET /api/v1/members/renewals — there
/// is no dedicated summary endpoint yet. If/when GET /api/v1/dashboard adds
/// renewal-bucket counts, swap this widget's data source for that instead.
class DashboardRenewalsCard extends StatefulWidget {
  /// Called when the Renewals screen reports that business data changed,
  /// so the parent Dashboard can refresh its own KPI tiles. This card
  /// always refreshes its own counts on return regardless of this callback
  /// (see openRenewals below) — onDataChanged is purely for the dashboard's
  /// separate totalMembers/activeMembers/expiredMembers state.
  final VoidCallback? onDataChanged;

  const DashboardRenewalsCard({super.key, this.onDataChanged});

  @override
  State<DashboardRenewalsCard> createState() =>
      _DashboardRenewalsCardState();
}

class _DashboardRenewalsCardState extends State<DashboardRenewalsCard> {
  bool isLoading = true;

  int dueToday = 0;
  int dueThisWeek = 0;
  int overdue = 0;

  @override
  void initState() {
    super.initState();
    loadCounts();
  }

  Future<void> loadCounts() async {
    try {
      final all = await RenewalService().getRenewalsDue();

      if (!mounted) return;

      setState(() {
        dueToday = all.where((r) => r.status == 'DUE_TODAY').length;

        dueThisWeek = all
            .where((r) => r.daysRemaining >= 0 && r.daysRemaining <= 7)
            .length;

        overdue = all.where((r) => r.status == 'EXPIRED').length;

        isLoading = false;
      });
    } catch (e) {
      debugPrint('DASHBOARD RENEWALS CARD ERROR: $e');
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> openRenewals() async {
    final changed = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const RenewalsScreen(),
      ),
    );

    // This card's own counts can be stale even if `changed` isn't strictly
    // true (e.g. a renewal happened, screen popped via the system back
    // gesture) — refreshing unconditionally here is cheap (one request)
    // and guarantees correctness without depending on the caller's exact
    // pop path.
    await loadCounts();

    if (changed == true) {
      widget.onDataChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: openRenewals,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Row(
            children: [
              const Icon(
                Icons.autorenew_rounded,
                color: Colors.orange,
              ),
              const SizedBox(width: 8),
              const Text(
                "Renewals",
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: AppColors.primary,
              ),
            ],
          ),

          const SizedBox(height: 18),

          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: DashboardCardStat(
                    value: dueToday.toString(),
                    label: "Due Today",
                    color: AppColors.danger,
                  ),
                ),
                const DashboardCardDivider(),
                Expanded(
                  child: DashboardCardStat(
                    value: dueThisWeek.toString(),
                    label: "Due This Week",
                    color: AppColors.warning,
                  ),
                ),
                const DashboardCardDivider(),
                Expanded(
                  child: DashboardCardStat(
                    value: overdue.toString(),
                    label: "Overdue",
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
