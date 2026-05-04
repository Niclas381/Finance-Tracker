import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF4CAF50),
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: const Color(0xFF101010),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF101010),
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF181818),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 2,
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(
        color: Colors.white70,
      ),
    ),
    useMaterial3: true,
  );
}
