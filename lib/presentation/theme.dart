// lib/presentation/theme.dart
//
// Design token source of truth. All colours, spacing, and text styles live
// here — no magic numbers in screen files.
//
// Spec v1.3 LOCKED tokens (do not change without a spec bump):
//   Background  : #0c0c0d  (near-black, not pure #000000 — OLED halation)
//   Accent      : #2FB083  (muted emerald/teal — the ONLY color that means
//                           anything: action / the thing to do now)
//   Energy icons: monochrome glyphs, shape-distinguished (no colour coding)
//   Heartbeat   : static fill, updates on state transition only (no idle anim)
//   Typography  : sans primary / mono for live numerals
//
// v-fix note: this file was previously truncated mid-declaration
// (`FloatingActionBut…`) and was missing tokens that widgets/ referenced
// (divider, surfaceRaised, textFaint). All are defined below.

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Colour tokens
// ---------------------------------------------------------------------------

class AppColors {
  // -- Locked spec v1.3 --
  static const background = Color(0xFF0C0C0D);
  static const accent = Color(0xFF2FB083);

  // -- Derived surfaces (elevation via lightness, not shadow) --
  static const surface = Color(0xFF161618); // cards
  static const surfaceRaised = Color(0xFF1C1C1F); // sheets, dialogs
  static const surfaceVariant = Color(0xFF212124); // inputs, chips
  static const divider = Color(0xFF232326);

  // -- Accent variants (accent stays the one signal; these are states of it)
  static const accentDim = Color(0xFF1E7A5A); // pressed / disabled action
  static const accentWash = Color(0x1A2FB083); // 10% — selected fill only

  // -- Text ramp --
  static const textPrimary = Color(0xFFF0F0F0);
  static const textSecondary = Color(0xFF8A8A8E);
  static const textMuted = Color(0xFF555559);
  static const textFaint = Color(0xFF3C3C40); // hints, placeholders

  // -- Semantic (mode indicator only — never energy coding, §13) --
  static const positive = accent;

  // v2 — the approved second functional color. Emerald means "action";
  // amber means "time attention": overtime, the T-2 warning, overdue.
  // Signal, not decoration — if it isn't about time, it isn't amber.
  static const attention = Color(0xFFD9A441);
  static const attentionWash = Color(0x1FD9A441); // 12% — tracks/chips only
  static const warning = attention; // legacy alias

  AppColors._();
}

// ---------------------------------------------------------------------------
// Spacing scale — 4pt grid. Use these instead of raw numbers.
// ---------------------------------------------------------------------------

class AppSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0; // screen gutter
  static const xxl = 32.0;

  /// Minimum tap target (Android accessibility floor).
  static const tapTarget = 48.0;

  /// Corner radii
  static const radiusCard = 14.0;
  static const radiusInput = 10.0;
  static const radiusSheet = 20.0;

  AppSpace._();
}

// ---------------------------------------------------------------------------
// Type scale
// ---------------------------------------------------------------------------

class AppTextStyles {
  // Sans primary (system Roboto on Android)

  /// The Next Best Action title — the loudest text in the app.
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

  /// Section eyebrows ("NEXT UP", "HABITS") — quiet structure.
  static const label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.textMuted,
    letterSpacing: 1.2,
  );

  // Monospace — live numerals only (heartbeat count, timers)
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

// ---------------------------------------------------------------------------
// ThemeData
// ---------------------------------------------------------------------------

class AppTheme {
  static ThemeData dark() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
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
        centerTitle: false,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.background,
        elevation: 2,
        highlightElevation: 2,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.background,
          disabledBackgroundColor: AppColors.accentDim,
          disabledForegroundColor: AppColors.background,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpace.radiusCard),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          minimumSize: const Size(AppSpace.tapTarget, AppSpace.tapTarget),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceVariant,
        hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textFaint),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpace.radiusInput),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpace.radiusInput),
          borderSide: const BorderSide(color: AppColors.accentDim, width: 1),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceRaised,
        contentTextStyle: AppTextStyles.bodyMedium,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpace.radiusInput),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceRaised,
        modalBackgroundColor: AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppSpace.radiusSheet)),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          // Calm, low-motion transition — consistent with §13 no-idle-anim rule.
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
