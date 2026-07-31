import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/plan_report.dart';
import '../../theme/app_colors.dart';

class PlanDistributionChart extends StatelessWidget {
  final PlanReport report;
  const PlanDistributionChart({super.key, required this.report});

  static const _pieColors = [
    AppColors.primary,
    Colors.deepPurple,
    AppColors.success,
    AppColors.warning,
    Colors.teal,
    Colors.indigo,
  ];

  @override
  Widget build(BuildContext context) {
    if (report.plans.isEmpty) {
      return Center(
        child: Text('No plan data yet',
            style: TextStyle(color: Colors.grey.shade400)),
      );
    }

    final totalRevenue =
        report.plans.fold(0.0, (s, p) => s + p.revenueInRupees);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (totalRevenue > 0) ...[
          const Text(
            'Plan Distribution by Revenue',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(height: 160, width: 160, child: _pieChart(totalRevenue)),
              const SizedBox(width: 20),
              Expanded(child: _legend()),
            ],
          ),
          const SizedBox(height: 24),
        ],
        // Plan stats table
        const Text(
          'Plan Performance',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 12),
        _planTable(),
      ],
    );
  }

  Widget _pieChart(double totalRevenue) {
    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 40,
        sections: report.plans.asMap().entries.map((e) {
          final i = e.key;
          final p = e.value;
          final pct = totalRevenue > 0
              ? p.revenueInRupees / totalRevenue * 100
              : 0.0;
          final color = _pieColors[i % _pieColors.length];
          return PieChartSectionData(
            value: p.revenueInRupees > 0 ? p.revenueInRupees : 0.1,
            color: color,
            radius: 40,
            title: pct > 8 ? '${pct.toStringAsFixed(0)}%' : '',
            titleStyle: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white),
          );
        }).toList(),
      ),
    );
  }

  Widget _legend() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: report.plans.asMap().entries.map((e) {
        final i = e.key;
        final p = e.value;
        final color = _pieColors[i % _pieColors.length];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(p.planName,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _planTable() {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(2),
        3: FlexColumnWidth(2),
      },
      children: [
        // Header
        TableRow(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          children: ['Plan', 'Members', 'Revenue', 'Sold']
              .map((h) => Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 8),
                    child: Text(h,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 12)),
                  ))
              .toList(),
        ),
        // Rows
        ...report.plans.map((p) => TableRow(
              decoration: BoxDecoration(
                border: Border(
                    bottom:
                        BorderSide(color: Colors.grey.shade200, width: 1)),
              ),
              children: [
                _cell(p.planName, bold: true),
                _cell('${p.activeMembers}'),
                _cell('₹${p.revenueInRupees.toStringAsFixed(0)}',
                    color: AppColors.success),
                _cell('${p.countSold}'),
              ],
            )),
      ],
    );
  }

  Widget _cell(String text, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          color: color,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
