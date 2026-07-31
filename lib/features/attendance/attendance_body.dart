import 'package:flutter/material.dart';

import '../../models/attendance_record.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_spacing.dart';

import 'attendance_record_card.dart';
import 'attendance_stats_row.dart';

/// Tabbed body: Today | History
/// All data is passed in from AttendanceScreen — this widget stays dumb.
class AttendanceBody extends StatelessWidget {
  final List<AttendanceRecord> todayRecords;
  final List<AttendanceRecord> recentRecords;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  const AttendanceBody({
    super.key,
    required this.todayRecords,
    required this.recentRecords,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          AttendanceStatsRow(
            todayCount: todayRecords.length,
            isLoading: isLoading,
          ),

          AppSpacing.gapLg,

          TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(text: 'Today'),
              Tab(text: 'Recent'),
            ],
          ),

          Expanded(
            child: TabBarView(
              children: [
                _list(todayRecords, 'No check-ins today yet'),
                _list(recentRecords, 'No recent check-ins'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(List<AttendanceRecord> records, String emptyMessage) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: records.isEmpty
          ? _emptyState(emptyMessage)
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 12),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: records.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AttendanceRecordCard(record: records[i]),
              ),
            ),
    );
  }

  Widget _emptyState(String message) {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            children: [
              Icon(
                Icons.event_available_rounded,
                size: 72,
                color: Colors.grey.shade300,
              ),
              const SizedBox(height: 20),
              Text(
                message,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
