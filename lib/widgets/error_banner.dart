import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'app_card.dart';

/// A friendly, user-facing error state with an optional retry action.
/// Always pass a message meant to be read by a user — never a raw
/// exception's `toString()`. Catch blocks should catch [ApiException]
/// (see services/api_response.dart) and pass its `.message` here.
///
/// Use [ErrorBanner] for a full-section replacement (e.g. a list screen
/// whose load failed) and [ErrorBanner.inline] for a compact strip above
/// otherwise-still-usable content.
class ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final bool compact;

  const ErrorBanner({
    super.key,
    required this.message,
    this.onRetry,
  }) : compact = false;

  const ErrorBanner.inline({
    super.key,
    required this.message,
    this.onRetry,
  }) : compact = true;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return AppCard(
        color: AppColors.danger.withValues(alpha: 0.06),
        bordered: false,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: AppTextStyles.body.copyWith(color: AppColors.danger),
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 56),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(140, 44),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
