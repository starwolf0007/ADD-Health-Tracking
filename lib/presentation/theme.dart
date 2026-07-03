// lib/presentation/theme.dart
//
// Design token source of truth. All colours and text styles live here.
// Spec v1.3 locked tokens:
//   Background  : #0c0c0d  (near-black, not pure #000000)
//   Accent      : #2FB083  (muted emerald / teal)
//   Energy icons: monochrome glyphs, shape-distinguished (no colour coding)
//   Heartbeat   : static fill, updates on state transition only (no idle anim)
//   Typography  : sans primary / mono for live numerals

import 'package:flutter/material.dart';

class AppColors {
  // -- Locked spec v1.3 tokens --
  static const background = Color(0xFF0C0C0D);
  static const surface = Color(0xFF161618);
  static const surfaceVariant = Color(0xFF1E1E21);
  static const accent = Color(0xFF2FB083);
  static const accentDim = Color(0xFF1E7A5A);

  // Text
  static const textPrimary = Color(0xFFF0F0F0);
  static const textSecondary = Color(0xFF8A8A8E);
  static const textMuted = Color(0xFF555559);

  // Semantic (mode indicator only — not energy coding)
  static const positive = Color(0xFF2FB083); // same as accent
  static const warning = Color(0xFFB08B2F);

  AppColors._();
}

class AppTextStyles {
  // Sans-serif primary (system default: Roboto on Android)
  static const displayLarge = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w300,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
  );

  static const titleMedium = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  static const bodyMedium = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  static const bodySmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  // Monospace — live numerals (heartbeat count, timers)
  static const monoLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w300,
    color: AppColors.accent,
    fontFeatures: [FontFeature.tabularFigures()],
    fontFamily: 'monospace',
  );

  static const monoSmall = TextStyle(
    fontSize: 13,
    color: AppColors.textSecondary,
    fontFeatures: [FontFeature.tabularFigures()],
    fontFamily: 'monospace',
  );

  AppTextStyles._();
}

class AppTheme {
  static ThemeData dark() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        // background / onBackground are deprecated in Flutter 3.22+.
        // scaffoldBackgroundColor above handles the canvas; surface covers cards.
        surface: AppColors.background, // scaffold canvas
        surfaceContainerHighest: AppColors.surface, // card / sheet surfaces
        primary: AppColors.accent,
        secondary: AppColors.accentDim,
        onSurface: AppColors.textPrimary,
        onPrimary: AppColors.background,
      ),
      cardTheme: const CardTheme(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.surfaceVariant,
        thickness: 1,
      ),
      textTheme: const TextTheme(
        displayLarge: AppTextStyles.displayLarge,
        titleMedium: AppTextStyles.titleMedium,
        bodyMedium: AppTextStyles.bodyMedium,
        bodySmall: AppTextStyles.bodySmall,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: AppTextStyles.titleMedium,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.background,
        elevation: 0,
      ),
    );
  }

  AppTheme._();
}
