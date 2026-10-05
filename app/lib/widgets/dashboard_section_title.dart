import 'package:flutter/material.dart';

class DashboardSectionTitle extends StatelessWidget {
  final String title;

  final String? actionText;

  final VoidCallback? onTap;

  const DashboardSectionTitle({
    super.key,
    required this.title,
    this.actionText,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),

        const Spacer(),

        if (actionText != null)
          TextButton(onPressed: onTap, child: Text(actionText!)),
      ],
    );
  }
}
