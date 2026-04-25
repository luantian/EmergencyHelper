import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static const Color primaryBlue = Color(0xFF67BAFF);
  static const Color pageBackground = Color(0xFFF3F5F7);
  static const Color lineColor = Color(0xFFE2E6EA);

  static ThemeData lightTheme() {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
    );

    return base.copyWith(
      scaffoldBackgroundColor: pageBackground,
      dividerColor: lineColor,
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
      ),
      cardTheme: const CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: Colors.white,
      ),
    );
  }
}
