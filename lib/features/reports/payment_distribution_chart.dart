import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/payment_report.dart';
import '../../theme/app_colors.dart';
import '../../utils/money.dart';

class PaymentDistributionChart extends StatelessWidget {
  final PaymentReport report;
  const PaymentDistributionChart({super.key, required this.report});

  static const _pieColors = [
    AppColors.primary,
    AppColors.success,
    AppColors.warning,
    Colors.deepPurple,
    Colors.teal,
  ];

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
            _kpi(
              'Collected',
              moneyShortR(report.collectedInRupees),
              AppColors.success,
            ),
            _kpi(
              'Pending',
              moneyShortR(report.pendingInRupees),
              AppColors.warning,
            ),
            _kpi(
              'Overdue',
              moneyShortR(report.overdueInRupees),
              AppColors.danger,
            ),
            _kpi('Count', '${report.collectedCount}', AppColors.primary),
          ],
        ),
        const SizedBox(height: 24),
        if (report.modeBreakdown.isNotEmpty) ...[
          const Text(
            'Payment Mode Distribution',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(height: 160, width: 160, child: _pieChart()),
              const SizedBox(width: 20),
              Expanded(child: _legend()),
            ],
          ),
        ] else
          Center(
            child: Text(
              'No payment data yet',
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

  Widget _pieChart() {
    final total = report.modeBreakdown.fold(
      0.0,
      (sum, m) => sum + m.amountInRupees,
    );

    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 40,
        sections: report.modeBreakdown.asMap().entries.map((e) {
          final i = e.key;
          final m = e.value;
          final pct = total > 0 ? m.amountInRupees / total * 100 : 0.0;
          final color = _pieColors[i % _pieColors.length];
          return PieChartSectionData(
            value: m.amountInRupees,
            color: color,
            radius: 40,
            title: '${pct.toStringAsFixed(0)}%',
            titleStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _legend() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: report.modeBreakdown.asMap().entries.map((e) {
        final i = e.key;
        final m = e.value;
        final color = _pieColors[i % _pieColors.length];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${m.label} (${m.count})',
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
