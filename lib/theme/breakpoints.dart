import 'package:flutter/widgets.dart';

/// Screen-size breakpoints, in one place.
///
/// GymCRM started as a desktop-only web app, so layouts assumed a wide window
/// by default. These are the thresholds below which a layout has to change
/// shape rather than just get narrower — a two-column hero squeezed into 375px
/// is not a smaller layout, it is a broken one.
class Breakpoints {
  const Breakpoints._();

  /// Phones. Below this, side-by-side layouts must stack.
  static const double mobile = 600;

  /// Tablets and small windows. Below this, multi-column grids drop a column.
  static const double tablet = 900;
}

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;

  bool get isMobile => screenWidth < Breakpoints.mobile;
  bool get isTablet =>
      screenWidth >= Breakpoints.mobile && screenWidth < Breakpoints.tablet;
  bool get isDesktop => screenWidth >= Breakpoints.tablet;

  /// Columns for a card grid at the current width.
  int get gridColumns {
    if (screenWidth < Breakpoints.mobile) return 1;
    if (screenWidth < Breakpoints.tablet) return 2;
    return 3;
  }

  /// Page padding — phones cannot afford 24px of gutter on each side.
  EdgeInsets get pagePadding => EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: isMobile ? 12 : 20,
      );
}
