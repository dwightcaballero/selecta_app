import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Available curated theme presets for Selecta Ops.
enum AppThemePreset {
  classicTeal,
  executiveNavy,
  selectaCrimson;

  String get label {
    switch (this) {
      case AppThemePreset.classicTeal:
        return 'Classic Teal';
      case AppThemePreset.executiveNavy:
        return 'Executive Navy';
      case AppThemePreset.selectaCrimson:
        return 'Selecta Crimson';
    }
  }

  String get description {
    switch (this) {
      case AppThemePreset.classicTeal:
        return 'Original familiar teal';
      case AppThemePreset.executiveNavy:
        return 'High contrast, calm & zero glare';
      case AppThemePreset.selectaCrimson:
        return 'Authentic Selecta brand red';
    }
  }

  Color get primaryColor {
    switch (this) {
      case AppThemePreset.classicTeal:
        return const Color(0xFF006684);
      case AppThemePreset.executiveNavy:
        return const Color(0xFF1E3A8A);
      case AppThemePreset.selectaCrimson:
        return const Color(0xFFC8102E);
    }
  }

  Color get darkPrimaryColor {
    switch (this) {
      case AppThemePreset.classicTeal:
        return const Color(0xFF14B8A6); // High-contrast, soothing teal (no electric glare)
      case AppThemePreset.executiveNavy:
        return const Color(0xFF3B82F6); // Calibrated royal slate-blue
      case AppThemePreset.selectaCrimson:
        return const Color(0xFFEF4444); // Authentic Selecta brand red
    }
  }

  static AppThemePreset fromString(String? value) {
    return AppThemePreset.values.firstWhere(
      (preset) => preset.name == value,
      orElse: () => AppThemePreset.classicTeal,
    );
  }
}

/// Centralized modern theme system for Selecta Ops.
/// Features Outfit for modern headings and Inter for crisp, legible body and data.
class AppTheme {
  static const Color accentAmber = Color(0xFFF59E0B);
  static const Color successGreen = Color(0xFF10B981);
  static const Color errorRed = Color(0xFFEF4444);

  // Surface colors — subtle whisper off-white to eliminate glare while keeping cards distinct
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightTextPrimary = Color(0xFF1E293B);
  static const Color lightTextSecondary = Color(0xFF64748B);

  // Dark mode surfaces — calm, soft-charcoal canvas with clearly elevated cards (no eye strain or halation)
  static const Color darkBg = Color(0xFF12161E);
  static const Color darkCard = Color(0xFF1E2430);
  static const Color darkBorder = Color(0xFF384152);
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFFCBD5E1); // Slate 300 for high-contrast, effortless reading

  // Backward compatibility getters
  static ThemeData get lightTheme => lightThemeFor(AppThemePreset.classicTeal);
  static ThemeData get darkTheme => darkThemeFor(AppThemePreset.classicTeal);

  /// Light theme builder for the chosen preset
  static ThemeData lightThemeFor(AppThemePreset preset) {
    final primaryColor = preset.primaryColor;
    final baseTextTheme = GoogleFonts.interTextTheme(ThemeData.light().textTheme);

    final textTheme = baseTextTheme.copyWith(
      displayLarge: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: lightTextPrimary),
      displayMedium: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: lightTextPrimary),
      headlineLarge: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: lightTextPrimary),
      headlineMedium: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: lightTextPrimary),
      headlineSmall: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: lightTextPrimary),
      titleLarge: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 18.5, color: lightTextPrimary),
      titleMedium: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 16.5, color: lightTextPrimary),
      titleSmall: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 14.5, color: lightTextPrimary),
      bodyLarge: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16, color: lightTextPrimary),
      bodyMedium: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 14.5, color: lightTextPrimary),
      bodySmall: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 12.5, color: lightTextSecondary),
      labelLarge: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14.5, color: lightTextPrimary),
      labelMedium: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5, color: lightTextPrimary),
      labelSmall: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11, color: lightTextSecondary),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        secondary: accentAmber,
        tertiary: successGreen,
        error: errorRed,
        surface: lightBg,
        surfaceContainer: lightCard,
        outline: lightBorder,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: lightBg,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: lightCard,
        foregroundColor: lightTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: lightTextPrimary,
        ),
        iconTheme: const IconThemeData(color: Color(0xFF334155)),
      ),
      cardTheme: CardThemeData(
        elevation: 1.5,
        shadowColor: Colors.black.withAlpha(20),
        color: lightCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: lightBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: const BorderSide(color: Color(0xFFCBD5E1)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: errorRed),
        ),
        labelStyle: GoogleFonts.inter(color: lightTextSecondary, fontSize: 14),
        hintStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: lightCard,
        selectedColor: primaryColor,
        disabledColor: const Color(0xFFE2E8F0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: const BorderSide(color: Color(0xFFCBD5E1)),
        labelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: lightTextPrimary,
        ),
        secondaryLabelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        checkmarkColor: Colors.white,
        iconTheme: const IconThemeData(size: 18, color: lightTextPrimary),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: lightCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: lightTextPrimary),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: lightCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        clipBehavior: Clip.antiAliasWithSaveLayer,
      ),
      dividerTheme: const DividerThemeData(
        color: lightBorder,
        thickness: 1,
        space: 1,
      ),
    );
  }

  /// Dark theme builder for the chosen preset
  static ThemeData darkThemeFor(AppThemePreset preset) {
    final darkPrimary = preset.darkPrimaryColor;
    final baseTextTheme = GoogleFonts.interTextTheme(ThemeData.dark().textTheme);

    final textTheme = baseTextTheme.copyWith(
      displayLarge: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: darkTextPrimary),
      displayMedium: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: darkTextPrimary),
      headlineLarge: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: darkTextPrimary),
      headlineMedium: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: darkTextPrimary),
      headlineSmall: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: darkTextPrimary),
      titleLarge: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 18.5, color: darkTextPrimary),
      titleMedium: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 16.5, color: darkTextPrimary),
      titleSmall: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 14.5, color: darkTextPrimary),
      bodyLarge: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16, color: darkTextPrimary),
      bodyMedium: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 14.5, color: darkTextPrimary),
      bodySmall: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 12.5, color: darkTextSecondary),
      labelLarge: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14.5, color: darkTextPrimary),
      labelMedium: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5, color: darkTextPrimary),
      labelSmall: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11, color: darkTextSecondary),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: preset.primaryColor,
        primary: darkPrimary,
        onPrimary: Colors.white,
        secondary: accentAmber,
        tertiary: successGreen,
        error: errorRed,
        surface: darkBg,
        surfaceContainer: darkCard,
        surfaceContainerHighest: const Color(0xFF28303F),
        onSurface: darkTextPrimary,
        onSurfaceVariant: darkTextSecondary,
        outline: darkBorder,
        outlineVariant: const Color(0xFF384152),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: darkBg,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: darkCard,
        foregroundColor: darkTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: darkTextPrimary,
        ),
        iconTheme: const IconThemeData(color: Color(0xFFF8FAFC)),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shadowColor: Colors.black.withAlpha(50),
        color: darkCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: darkBorder, width: 1.2),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: const BorderSide(color: darkBorder, width: 1.2),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkBorder, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkBorder, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: darkPrimary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: errorRed, width: 1.2),
        ),
        labelStyle: GoogleFonts.inter(color: darkTextSecondary, fontSize: 14, fontWeight: FontWeight.w500),
        hintStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: darkCard,
        selectedColor: darkPrimary,
        disabledColor: const Color(0xFF28303F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: const BorderSide(color: darkBorder),
        labelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: darkTextPrimary,
        ),
        secondaryLabelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        checkmarkColor: Colors.white,
        iconTheme: const IconThemeData(size: 18, color: darkTextPrimary),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: darkPrimary,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: darkBorder, width: 1.2),
        ),
        titleTextStyle: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: darkTextPrimary),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        clipBehavior: Clip.antiAliasWithSaveLayer,
      ),
      dividerTheme: const DividerThemeData(
        color: darkBorder,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
