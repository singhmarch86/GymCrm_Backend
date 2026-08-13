import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/renewal_report.dart';
import '../../theme/app_colors.dart';

class RenewalTrendChart extends StatelessWidget {
  final RenewalReport report;
  const RenewalTrendChart({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _kpi('Due Today', '${report.dueToday}', AppColors.warning),
            _kpi(
              'Completed This Month',
              '${report.completedThisMonth}',
              AppColors.success,
            ),
            _kpi(
              'Success Rate',
              '${report.successRate.toStringAsFixed(0)}%',
              report.successRate >= 70 ? AppColors.success : AppColors.warning,
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (report.trend.isNotEmpty &&
            report.trend.any((t) => t.count > 0)) ...[
          const Text(
            'Monthly Renewals',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 12),
          SizedBox(height: 160, child: _barChart()),
        ] else
          Center(
            child: Text(
              'No renewal data yet',
              style: TextStyle(color: Colors.grey.shade400),
            ),
          ),
      ],
    );
  }

  Widget _kpi(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _barChart() {
    final maxY =
        report.trend
            .map((t) => t.count.toDouble())
            .fold(0.0, (a, b) => a > b ? a : b) *
        1.3;

    return BarChart(
      BarChartData(
        maxY: maxY > 0 ? maxY : 5,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: Colors.grey.shade200, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, _) {
                final i = value.toInt();
                if (i < 0 || i >= report.trend.length) {
                  return const SizedBox.shrink();
                }
                if (i % 3 != 0) return const SizedBox.shrink();
                final label = report.trend[i].month.split(' ')[0];
                return Text(
                  label,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                );
              },
            ),
          ),
        ),
        barGroups: report.trend.asMap().entries.map((e) {
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: e.value.count.toDouble(),
                color: AppColors.primary,
                width: 14,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
