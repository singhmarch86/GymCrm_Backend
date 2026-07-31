import 'package:flutter/material.dart';

class AppColors {
  // Warm coral — the app's brand/accent color (buttons, links, focus rings,
  // Material ColorScheme seed). Distinct from the semantic status colors
  // below, which carry their own meaning (paid/active = green, overdue =
  // red) independent of the brand palette.
  static const primary = Color(0xFFEA580C);
  static const primaryLight = Color(0xFFFFF7ED);

  static const success = Color(0xFF16A34A);
  static const successLight = Color(0xFFDCFCE7);

  static const warning = Color(0xFFF59E0B);
  static const warningLight = Color(0xFFFEF3C7);

  static const danger = Color(0xFFDC2626);
  static const dangerLight = Color(0xFFFEE2E2);

  // Cool complementary accent — used sparingly to break up screens that
  // would otherwise be all-coral (e.g. a KPI row sitting next to the
  // primary-colored "Members" card).
  static const info = Color(0xFF0891B2);
  static const infoLight = Color(0xFFCFFAFE);

  static const background = Color(0xFFFFF8F6);

  static const card = Colors.white;

  static const textPrimary = Color(0xFF111827);

  static const textSecondary = Color(0xFF6B7280);

  static const border = Color(0xFFE5E7EB);
}