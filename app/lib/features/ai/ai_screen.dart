import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// AI Insights screen — scaffold placeholder.
/// Business logic will be implemented as part of the AI Insights module sprint.
class AiScreen extends StatefulWidget {
  const AiScreen({super.key});

  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Insights')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 72,
              color: AppColors.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 24),
            const Text(
              'AI Insights',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Coming soon',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
