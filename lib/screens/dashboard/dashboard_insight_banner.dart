import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// "Alert-first" dashboard layout: whatever needs the owner's attention
/// today — members going quiet, renewals about to lapse — surfaces here,
/// above the KPI grid, instead of being buried in a stat the owner has to
/// go looking for. Renders nothing if there's nothing to flag.
///
/// All three inputs are fields the dashboard endpoint already returns
/// (see DashboardResponse) — no new backend work.
class DashboardInsightBanner extends StatelessWidget {
  final int inactive14Days;
  final int inactive30Days;
  final int expiring7Days;

  const DashboardInsightBanner({
    super.key,
    required this.inactive14Days,
    required this.inactive30Days,
    required this.expiring7Days,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    // Churn risk takes priority: a member who's gone quiet for 30+ days is
    // a bigger concern than one who's merely due for renewal. Only show the
    // more urgent of the two 14/30-day churn signals, not both at once.
    if (inactive30Days > 0) {
      rows.add(_InsightRow(
        icon: Icons.person_off_outlined,
        color: AppColors.danger,
        background: AppColors.dangerLight,
        title:
            '$inactive30Days member${inactive30Days == 1 ? '' : 's'} inactive for 30+ days',
        subtitle: 'At risk of lapsing — worth a check-in call.',
        tooltip:
            'Members with no gym check-in in the last 30 days are flagged as at risk of lapsing.',
      ));
    } else if (inactive14Days > 0) {
      rows.add(_InsightRow(
        icon: Icons.person_off_outlined,
        color: AppColors.warning,
        background: AppColors.warningLight,
        title:
            '$inactive14Days member${inactive14Days == 1 ? '' : 's'} inactive for 14+ days',
        subtitle: 'Attendance has dropped off — keep an eye on this.',
        tooltip: 'Members with no gym check-in in the last 14 days.',
      ));
    }

    if (expiring7Days > 0) {
      rows.add(_InsightRow(
        icon: Icons.schedule_rounded,
        color: AppColors.warning,
        background: AppColors.warningLight,
        title:
            '$expiring7Days renewal${expiring7Days == 1 ? '' : 's'} due within 7 days',
        subtitle: 'Follow up before their membership lapses.',
        tooltip: 'Active members whose plan expires within the next 7 days.',
      ));
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows) ...[row, const SizedBox(height: 8)],
        ],
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String subtitle;
  final String? tooltip;

  const _InsightRow({
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    required this.subtitle,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title. $subtitle',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            if (tooltip != null)
              Tooltip(
                message: tooltip!,
                triggerMode: TooltipTriggerMode.tap,
                child: Icon(Icons.info_outline_rounded, color: color.withValues(alpha: 0.7), size: 16),
              ),
          ],
        ),
      ),
    );
  }
}
