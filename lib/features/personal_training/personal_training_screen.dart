import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Personal Training screen — scaffold placeholder.
/// Business logic will be implemented as part of the Personal Training module sprint.
class PersonalTrainingScreen extends StatefulWidget {
  const PersonalTrainingScreen({super.key});

  @override
  State<PersonalTrainingScreen> createState() => _PersonalTrainingScreenState();
}

class _PersonalTrainingScreenState extends State<PersonalTrainingScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Personal Training'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.fitness_center_rounded,
              size: 72,
              color: Colors.deepPurple.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 24),
            const Text(
              'Personal Training',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Coming soon',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
