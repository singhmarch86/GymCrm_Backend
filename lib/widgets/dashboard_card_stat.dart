import 'package:flutter/material.dart';

/// One value+label column inside a 3-up stat row on a dashboard summary
/// card (Renewals, Revenue). Shared so both cards render identically
/// instead of each keeping its own near-duplicate private widget.
class DashboardCardStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final double fontSize;

  const DashboardCardStat({
    super.key,
    required this.value,
    required this.label,
    required this.color,
    this.fontSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Vertical divider between stats in the row described above.
class DashboardCardDivider extends StatelessWidget {
  const DashboardCardDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 40, color: Colors.grey.shade200);
  }
}
