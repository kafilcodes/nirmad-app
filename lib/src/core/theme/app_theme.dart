import 'package:flutter/material.dart';
import '../ui/animation_policies.dart';

class AppTheme {
  // Global accent: purplish (#6C63FF)
  static const _seed = Color(0xFF6C63FF);

  static ThemeData get light {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.light),
      useMaterial3: true,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
    return base.copyWith(
  pageTransitionsTheme: AppAnimations.pageTransitions,
      cardTheme: base.cardTheme.copyWith(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: base.colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: base.colorScheme.primary, width: 2),
        ),
        filled: true,
  fillColor: base.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
    );
  }

  static ThemeData get dark {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
      useMaterial3: true,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
    return base.copyWith(
  pageTransitionsTheme: AppAnimations.pageTransitions,
      cardTheme: base.cardTheme.copyWith(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: base.colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: base.colorScheme.primary, width: 2),
        ),
        filled: true,
  fillColor: base.colorScheme.surfaceContainerHighest.withValues(alpha: 0.12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
    );
  }
}
