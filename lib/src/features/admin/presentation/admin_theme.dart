import 'package:flutter/material.dart';

class AdminTheme {
  static ThemeData get amoledDark {
    const bg = Color(0xFF000000);
    const card = Color(0xFF0B0B0B);
    const surface = Color(0xFF0F1011);
    // Cyan accent
    const primary = Color(0xFF00BCD4); // Cyan 500
    const onPrimary = Colors.black;
    const text = Color(0xFFEAEAEA);

    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: primary,
      onPrimary: onPrimary,
      secondary: Color(0xFF26C6DA),
      onSecondary: text,
      error: Color(0xFFEF5350),
      onError: Colors.white,
      surface: surface,
      onSurface: text,
    );

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      useMaterial3: true,
      brightness: Brightness.dark,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: bg,
        foregroundColor: text,
        centerTitle: false,
      ),
      cardColor: card,
      cardTheme: const CardThemeData(
        elevation: 0,
        color: card,
        margin: EdgeInsets.all(8),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF121212),
        contentTextStyle: TextStyle(color: text),
      ),
      dividerColor: const Color(0x22FFFFFF),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: text),
        bodySmall: TextStyle(color: Color(0xFFBFBFBF)),
        titleMedium: TextStyle(color: text, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(color: text, fontWeight: FontWeight.w700),
      ),
      iconTheme: const IconThemeData(color: Color(0xFFBFBFBF)),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Color(0xFF151516),
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}
