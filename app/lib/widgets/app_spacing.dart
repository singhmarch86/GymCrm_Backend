import 'package:flutter/widgets.dart';

/// Centralized spacing system used across the application.
///
/// Usage:
/// const SizedBox(height: AppSpacing.lg)
/// const SizedBox(width: AppSpacing.md)
///
/// Or:
/// padding: const EdgeInsets.all(AppSpacing.lg);

class AppSpacing {
  AppSpacing._();

  // Base spacing scale
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;

  // Common paddings
  static const EdgeInsets screenPadding = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: lg,
  );

  static const EdgeInsets cardPadding = EdgeInsets.all(lg);

  static const EdgeInsets tilePadding = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: md,
  );

  // Common gaps
  static const SizedBox gapXs = SizedBox(height: xs);

  static const SizedBox gapSm = SizedBox(height: sm);

  static const SizedBox gapMd = SizedBox(height: md);

  static const SizedBox gapLg = SizedBox(height: lg);

  static const SizedBox gapXl = SizedBox(height: xl);

  static const SizedBox gapXxl = SizedBox(height: xxl);

  // Horizontal gaps
  static const SizedBox hGapSm = SizedBox(width: sm);

  static const SizedBox hGapMd = SizedBox(width: md);

  static const SizedBox hGapLg = SizedBox(width: lg);

  static const SizedBox hGapXl = SizedBox(width: xl);
}
