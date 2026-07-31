import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/revenue_report.dart';
import '../../theme/app_colors.dart';

class RevenueChart extends StatelessWidget {
  final RevenueReport report;
  const RevenueChart({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // KPI row
        _kpiRow(),
        const SizedBox(height: 24),
        // Trend chart
        if (report.trend.isNotEmpty) ...[
          const Text(
            '12-Month Revenue Trend',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 12),
          SizedBox(height: 180, child: _lineChart()),
        ] else
          _noChartData(),
      ],
    );
  }

  Widget _kpiRow() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _kpi('Today', '₹${report.todayInRupees.toStringAsFixed(0)}', AppColors.success),
        _kpi('Yesterday', '₹${report.yesterdayInRupees.toStringAsFixed(0)}', Colors.blueGrey),
        _kpi('This Week', '₹${report.weekInRupees.toStringAsFixed(0)}', AppColors.primary),
        _kpi('This Month', '₹${report.monthInRupees.toStringAsFixed(0)}', Colors.deepPurple),
        _kpi('Last Month', '₹${report.lastMonthInRupees.toStringAsFixed(0)}', Colors.teal),
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

  Widget _lineChart() {
    final spots = report.trend.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.revenueInRupees);
    }).toList();

    final maxY = report.trend
            .map((t) => t.revenueInRupees)
            .fold(0.0, (a, b) => a > b ? a : b) *
        1.2;

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY > 0 ? maxY : 1000,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: Colors.grey.shade200, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, _) {
                final i = value.toInt();
                if (i < 0 || i >= report.trend.length) {
                  return const SizedBox.shrink();
                }
                // Show only every 3rd label to avoid crowding
                if (i % 3 != 0) return const SizedBox.shrink();
                final label = report.trend[i].month.split(' ')[0]; // "Jan"
                return Text(label,
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey.shade500));
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppColors.primary,
            barWidth: 2.5,
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.primary.withValues(alpha: 0.08),
            ),
            dotData: FlDotData(
              show: true,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 3,
                color: AppColors.primary,
                strokeWidth: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noChartData() {
    return Center(
      child: Text(
        'No trend data yet',
        style: TextStyle(color: Colors.grey.shade400),
      ),
    );
  }
}
