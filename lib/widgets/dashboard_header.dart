import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class DashboardHeader extends StatelessWidget {
  final String userName;
  final String role;
  final VoidCallback onLogout;

  const DashboardHeader({
    super.key,
    required this.userName,
    required this.role,
    required this.onLogout,
  });

  String _greeting() {
    final hour = DateTime.now().hour;

    if (hour < 12) {
      return "Good Morning";
    }

    if (hour < 17) {
      return "Good Afternoon";
    }

    return "Good Evening";
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: AppColors.primary,

          child: Text(
            userName.isNotEmpty ? userName[0].toUpperCase() : "G",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        const SizedBox(width: 16),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "👋 ${_greeting()}",
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),

              const SizedBox(height: 4),

              Text(
                userName,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 2),

              Text(role, style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),

        IconButton(
          tooltip: "Logout",
          onPressed: onLogout,
          icon: const Icon(Icons.logout_rounded),
        ),
      ],
    );
  }
}
