import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Workout Plans screen — scaffold placeholder.
/// Business logic will be implemented as part of the Workout Plans module sprint.
class WorkoutsScreen extends StatefulWidget {
  const WorkoutsScreen({super.key});

  @override
  State<WorkoutsScreen> createState() => _WorkoutsScreenState();
}

class _WorkoutsScreenState extends State<WorkoutsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workout Plans')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.directions_run_rounded,
              size: 72,
              color: Colors.teal.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 24),
            const Text(
              'Workout Plans',
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
