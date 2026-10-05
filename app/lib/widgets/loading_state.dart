import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Full-screen loading view for a screen's first load (replaces the whole
/// body — use when there's nothing else useful to show yet).
class LoadingView extends StatelessWidget {
  final String? label;

  const LoadingView({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2.5,
          ),
          if (label != null) ...[
            const SizedBox(height: 16),
            Text(label!, style: AppTextStyles.caption),
          ],
        ],
      ),
    );
  }
}

/// Small inline spinner for list-scoped loads where the app bar / filters /
/// scaffold chrome should stay visible while the content area loads.
class InlineLoadingView extends StatelessWidget {
  const InlineLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}
