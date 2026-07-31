import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Branch Management screen — scaffold placeholder.
/// Business logic will be implemented as part of the Branch Management module sprint.
class BranchScreen extends StatefulWidget {
  const BranchScreen({super.key});

  @override
  State<BranchScreen> createState() => _BranchScreenState();
}

class _BranchScreenState extends State<BranchScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Branch Management'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.store_rounded,
              size: 72,
              color: Colors.blueGrey.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 24),
            const Text(
              'Branch Management',
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
