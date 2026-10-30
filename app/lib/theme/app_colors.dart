import 'package:flutter/material.dart';

class AppColors {
  // Brand palette, taken from the Kyokushin seal: navy ring, red emblem,
  // yellow border. Navy carries the UI (buttons, active tabs, focus rings,
  // Material ColorScheme seed); red is the accent, used in the
  // wordmark and for emphasis; yellow is
  // a highlight for badges and selected chips, never a text color on white.
  // These are distinct from the semantic status colors below, which carry
  // their own meaning (paid/active = green, overdue = crimson) independent of
  // the brand palette.
  static const primary = Color(0xFF2F3B86);
  static const primaryLight = Color(0xFFE8EBF7);

  static const accent = Color(0xFFD8231B);
  static const highlight = Color(0xFFFFD400);

  static const success = Color(0xFF16A34A);
  static const successLight = Color(0xFFDCFCE7);

  static const warning = Color(0xFFF59E0B);
  static const warningLight = Color(0xFFFEF3C7);

  // Deliberately deeper than the brand [accent] red, so an overdue badge is
  // never mistaken for a brand button.
  static const danger = Color(0xFFB42318);
  static const dangerLight = Color(0xFFFEE4E2);

  // Cool complementary accent — used sparingly to break up screens that
  // would otherwise be all-navy (e.g. a KPI row sitting next to the
  // primary-colored "Members" card).
  static const info = Color(0xFF0891B2);
  static const infoLight = Color(0xFFCFFAFE);

  static const background = Color(0xFFF6F7FB);

  static const card = Colors.white;

  static const textPrimary = Color(0xFF111827);

  static const textSecondary = Color(0xFF6B7280);

  static const border = Color(0xFFE5E7EB);
}
