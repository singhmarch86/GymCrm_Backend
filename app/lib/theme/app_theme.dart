import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTheme {
  /// Style for an ElevatedButton placed inside a horizontal action row
  /// (dialog footers, AlertDialog actions).
  ///
  /// The global elevatedButtonTheme below sets `minimumSize` to
  /// `Size(double.infinity, 52)` so full-width page buttons (login, register)
  /// need no extra styling. That default is actively harmful in a Row: a Row
  /// lays out non-flexible children with an *unbounded* width constraint, so
  /// an infinite minimum width makes the button overflow the dialog and get
  /// clipped out of view entirely — the button is still there and still
  /// tappable in theory, but the user simply cannot see it. Any button in a
  /// row must therefore opt out with a finite minimum size.
  static final ButtonStyle dialogActionButton = ElevatedButton.styleFrom(
    minimumSize: const Size(120, 48),
  );

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,

    scaffoldBackgroundColor: AppColors.background,

    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
      centerTitle: false,
    ),

    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,

      // Without an explicit hintStyle, Flutter's default renders placeholder
      // text nearly as dark as real input — so an example like "Annual
      // Membership — Gold" reads as if the user already typed it, and a
      // "required field" error then looks like a bug. Hints must be visibly
      // lighter than entered text, everywhere in the app.
      hintStyle: const TextStyle(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w400,
      ),

      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    ),
  );
}
