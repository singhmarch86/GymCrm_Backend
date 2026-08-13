import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';

/// Compact KPI row shown at the top of the Attendance screen.
class AttendanceStatsRow extends StatelessWidget {
  final int todayCount;
  final bool isLoading;

  const AttendanceStatsRow({
    super.key,
    required this.todayCount,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: isLoading
          ? const Center(
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Row(
              children: [
                _stat(
                  Icons.today_rounded,
                  'Today',
                  '$todayCount',
                  AppColors.success,
                ),
                _divider(),
                _stat(
                  Icons.calendar_view_week_rounded,
                  'This Week',
                  '—',
                  AppColors.primary,
                ),
                _divider(),
                _stat(
                  Icons.calendar_month_rounded,
                  'This Month',
                  '—',
                  Colors.deepPurple,
                ),
              ],
            ),
    );
  }

  Widget _stat(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _divider() =>
      Container(width: 1, height: 50, color: Colors.grey.shade200);
}
