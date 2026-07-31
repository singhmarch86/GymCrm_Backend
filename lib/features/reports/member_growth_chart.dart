import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/member_report.dart';
import '../../theme/app_colors.dart';

class MemberGrowthChart extends StatelessWidget {
  final MemberReport report;
  const MemberGrowthChart({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // KPI row
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _kpi('Total', '${report.total}', AppColors.primary),
            _kpi('Active', '${report.active}', AppColors.success),
            _kpi('Expired', '${report.expired}', AppColors.danger),
            _kpi('New This Month', '${report.newThisMonth}', Colors.teal),
            _kpi(
              'Growth',
              '${report.growthPct >= 0 ? '+' : ''}${report.growthPct.toStringAsFixed(1)}%',
              report.growthPct >= 0 ? AppColors.success : AppColors.danger,
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (report.growth.isNotEmpty &&
            report.growth.any((p) => p.joined > 0 || p.expired > 0)) ...[
          const Text(
            '12-Month Member Growth',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 4),
          // Legend
          Row(
            children: [
              _dot(AppColors.success),
              const SizedBox(width: 4),
              Text('Joined',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              const SizedBox(width: 12),
              _dot(AppColors.danger.withValues(alpha: 0.7)),
              const SizedBox(width: 4),
              Text('Expired',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(height: 180, child: _barChart()),
        ] else
          Center(
            child: Text('No growth data yet',
                style: TextStyle(color: Colors.grey.shade400)),
          ),
      ],
    );
  }

  Widget _dot(Color color) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

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
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _barChart() {
    final maxY = report.growth
            .map((p) => p.joined > p.expired ? p.joined : p.expired)
            .fold(0, (a, b) => a > b ? a : b)
            .toDouble() *
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
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, _) {
                final i = value.toInt();
                if (i < 0 || i >= report.growth.length) {
                  return const SizedBox.shrink();
                }
                if (i % 3 != 0) return const SizedBox.shrink();
                final label = report.growth[i].month.split(' ')[0];
                return Text(label,
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey.shade500));
              },
            ),
          ),
        ),
        barGroups: report.growth.asMap().entries.map((e) {
          final i = e.key;
          final p = e.value;
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                  toY: p.joined.toDouble(),
                  color: AppColors.success,
                  width: 6,
                  borderRadius: BorderRadius.circular(3)),
              BarChartRodData(
                  toY: p.expired.toDouble(),
                  color: AppColors.danger.withValues(alpha: 0.7),
                  width: 6,
                  borderRadius: BorderRadius.circular(3)),
            ],
            barsSpace: 2,
          );
        }).toList(),
      ),
    );
  }
}
