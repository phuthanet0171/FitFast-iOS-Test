import 'package:flutter/material.dart';

class AppColors {
  static const navy = Color(0xFF152238);
  static const teal = Color(0xFF20A486);
  static const tealDark = Color(0xFF137963);
  static const mint = Color(0xFFE9F7F3);
  static const orange = Color(0xFFFF7A4D);
  static const orangeSoft = Color(0xFFFFEFE9);
  static const blue = Color(0xFF5578EE);
  static const amber = Color(0xFFFFC34D);
  static const purple = Color(0xFF8C72D9);
  static const surface = Color(0xFFF6F8FA);
  static const border = Color(0xFFE7ECF0);
  static const muted = Color(0xFF718096);
}

class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.teal,
      primary: AppColors.teal,
      secondary: AppColors.orange,
      surface: Colors.white,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.surface,
      fontFamily: 'sans-serif',
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: AppColors.navy,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          color: AppColors.navy,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: TextStyle(
          color: AppColors.navy,
          fontWeight: FontWeight.w700,
        ),
        bodyMedium: TextStyle(color: AppColors.navy),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navy,
        actionTextColor: const Color(0xFF7BE0C6),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.teal,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
