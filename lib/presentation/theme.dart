// lib/presentation/theme.dart
//
// Design token source of truth. All colours, spacing, and text styles live
// here — no magic numbers in screen files.

import 'package:flutter/material.dart';

class AppColors {
  // -- Locked spec v1.3 tokens --
  static const background = Color(0xFF0C0C0D);
  static const accent = Color(0xFF2FB083);
  static const accentDim = Color(0xFF1E7A5A);
  static const accentWash = Color(0x1A2FB083); // 10%

  // Surfaces
  static const surface = Color(0xFF161618);
  static const surfaceRaised = Color(0xFF1C1C1F);
  static const surfaceVariant = Color(0xFF212124);
  static const divider = Color(0xFF232326);

  // Text
  static const textPrimary = Color(0xFFF0F0F0);
  static const textSecondary = Color(0xFF8A8A8E);
  static const textMuted = Color(0xFF555559);
  static const textFaint = Color(0xFF3C3C40);

  // Semantic
  static const warning = Color(0xFFD9A441);
  static const attention = Color(0xFFD9A441);

  AppColors._();
}

class AppSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 32.0;

  static const tapTarget = 48.0;

  static const radiusCard = 14.0;
  static const radiusInput = 10.0;
  static const radiusSheet = 20.0;

  AppSpace._();
}

class AppTextStyles {
  static const displayLarge = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    letterSpacing: -0.4,
    height: 1.25,
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
    height: 1.35,
  );

  static const label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.textMuted,
    letterSpacing: 1.2,
  );

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
        surface: AppColors.background,
        surfaceContainerHighest: AppColors.surface,
        primary: AppColors.accent,
        secondary: AppColors.accentDim,
        onSurface: AppColors.textPrimary,
        onPrimary: AppColors.background,
        error: AppColors.warning,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      textTheme: const TextTheme(
        displayLarge: AppTextStyles.displayLarge,
        titleMedium: AppTextStyles.titleMedium,
        bodyMedium: AppTextStyles.bodyMedium,
        bodySmall: AppTextStyles.bodySmall,
        labelSmall: AppTextStyles.label,
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
        elevation: 2,
      ),
    );
  }

  AppTheme._();
}
