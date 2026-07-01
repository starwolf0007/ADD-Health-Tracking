// lib/presentation/theme.dart
//
// PRESENTATION LAYER. The §13 locked tokens, realized as Flutter constants.
// Nothing in lib/presentation/ should hardcode a color outside this file —
// that's what "single source of truth for mockup and build" means in practice.

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  /// Near-black, not pure #000000 — pure black causes more halation/smear on
  /// OLED while scrolling (§13, locked v1.3).
  static const background = Color(0xFF0C0C0D);

  /// One step up from background — cards, sheets. Still restrained, never
  /// competes with the accent.
  static const surface = Color(0xFF18181A);
  static const surfaceRaised = Color(0xFF222225);

  /// The ENTIRE signal layer. One value, one meaning: action / the thing to
  /// do now. Never spent on decoration (§13).
  static const accent = Color(0xFF2FB083);

  /// Text + the monochrome energy glyphs (§13: shape, not color).
  static const textPrimary = Color(0xFFEDEDEF);
  static const textSecondary = Color(0xFF9A9AA2);
  static const textFaint = Color(0xFF5C5C63);

  static const divider = Color(0xFF2A2A2D);
}

class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.background,
        primary: AppColors.accent,
        onPrimary: Colors.white,
        secondary: AppColors.accent,
      ),
      // Sans-serif primary; the spec leaves monospace-for-numerals as a
      // recommendation, not yet locked (§13 note) — default platform sans
      // for everything in this phase, revisit if/when typography is locked.
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 26,
        ),
        titleMedium: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 17,
        ),
        bodyMedium: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
        ),
        bodySmall: TextStyle(
          color: AppColors.textFaint,
          fontSize: 12,
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 20),
      dividerColor: AppColors.divider,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
    );
  }
}
