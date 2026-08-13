import 'package:flutter/material.dart';

import '../../widgets/app_card.dart';

class DashboardRecentActivity extends StatelessWidget {
  const DashboardRecentActivity({super.key});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          Icon(Icons.timeline_rounded, size: 56, color: Colors.grey.shade400),

          const SizedBox(height: 20),

          const Text(
            "No Recent Activity",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 12),

          Text(
            "Member registrations,\nrenewals and payments\nwill appear here.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, height: 1.6),
          ),

          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              "Coming in Sprint 2",
              style: TextStyle(
                color: Colors.blue.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
