import 'package:flutter/material.dart';

import 'app_card.dart';

class DashboardKpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  final Color color;

  final String? subtitle;

  final VoidCallback? onTap;

  const DashboardKpiCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: subtitle != null ? '$title: $value, $subtitle' : '$title: $value',
      button: onTap != null,
      excludeSemantics: true,
      child: AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius:
              BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),

          const SizedBox(height: 22),

          Text(
            value,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),

          if (subtitle != null) ...[
            const SizedBox(height: 10),
            Text(
              subtitle!,
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }
}