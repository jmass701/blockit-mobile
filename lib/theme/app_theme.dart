/// AppTheme — the Flutter Material translation of the web dashboard's CSS custom
/// properties (see dashboard_static/index.html :root). Same teal primary, the
/// same grays/red/green semantic colors, 16px/12px corner radii, Inter font
/// (via google_fonts). Keeping the constants in one place mirrors the CSS
/// variables so the two products read as the same brand.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const teal = Color(0xFF0D9488);
  static const tealDark = Color(0xFF0F766E);
  static const tealBg = Color(0xFFCCFBF1);
  static const bg = Color(0xFFF7F8FA);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF111827);
  static const gray500 = Color(0xFF6B7280);
  static const gray200 = Color(0xFFE5E7EB);
  static const gray100 = Color(0xFFF3F4F6);
  static const redBg = Color(0xFFFEE2E2);
  static const red = Color(0xFFDC2626);
  static const greenBg = Color(0xFFD1FAE5);
  static const green = Color(0xFF059669);

  // Amber — the "pending / waiting" badge and the unlock banner.
  static const amberBg = Color(0xFFFEF3C7);
  static const amber = Color(0xFFD97706);
  static const bannerBg = Color(0xFFFFFBEB);
  static const bannerBorder = Color(0xFFFDE68A);
}

class AppRadius {
  static const double lg = 16;
  static const double md = 12;
  static const double sm = 10;
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.teal,
        primary: AppColors.teal,
        brightness: Brightness.light,
      ).copyWith(
        surface: AppColors.card,
        error: AppColors.red,
      ),
    );

    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.card,
        surfaceTintColor: AppColors.card,
        foregroundColor: AppColors.ink,
        elevation: 0,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.gray200),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.gray200, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.gray200, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.teal, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.teal,
          foregroundColor: Colors.white,
          textStyle:
              GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.tealDark,
          side: const BorderSide(color: AppColors.teal, width: 1.5),
          textStyle:
              GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
      ),
    );
  }

  /// The uppercase, letter-spaced gray label used for section titles / field
  /// labels throughout the web UI (.section-title / .field-group label).
  static TextStyle sectionLabel() => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.gray500,
        letterSpacing: 0.6,
      );
}
