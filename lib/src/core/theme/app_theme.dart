import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart';
import '../ui/animation_policies.dart';

class AppTheme {
  // Global accent / brand primary color
  static const _seed = Color(0xFF5148FB); // brand accent / seed for tonal palette
  static const _primary = Color(0xFF9D9DFB); // latest lighter primary (distinct from accent)

  // Normalize text metrics to avoid top/bottom imbalance with certain fonts
  static TextTheme _normalizeTextTheme(TextTheme t) {
    TextStyle? tune(TextStyle? s, {double? height}) =>
        s?.copyWith(
          leadingDistribution: TextLeadingDistribution.proportional,
          height: height ?? s.height,
          textBaseline: TextBaseline.alphabetic,
        );
    return t.copyWith(
      displayLarge: tune(t.displayLarge),
      displayMedium: tune(t.displayMedium),
      displaySmall: tune(t.displaySmall),
      headlineLarge: tune(t.headlineLarge),
      headlineMedium: tune(t.headlineMedium),
      headlineSmall: tune(t.headlineSmall),
      titleLarge: tune(t.titleLarge),
      // TextFields commonly use titleMedium; give a slightly taller line to center better
      titleMedium: tune(t.titleMedium, height: 1.2),
      titleSmall: tune(t.titleSmall),
      // Body text gets a modest line-height to avoid cramped look across devices
      bodyLarge: tune(t.bodyLarge, height: 1.2),
      bodyMedium: tune(t.bodyMedium, height: 1.2),
      bodySmall: tune(t.bodySmall),
  // Buttons/Chips rely on label* – use tight height for precise vertical centering
  labelLarge: tune(t.labelLarge, height: 1.0),
  labelMedium: tune(t.labelMedium, height: 1.0),
  labelSmall: tune(t.labelSmall, height: 1.0),
    );
  }

  static ThemeData get light {
    final generated = ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.light);
    final scheme = generated.copyWith(
      primary: _primary,
      onPrimary: Colors.black, // ensure contrast on lighter primary
    );
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
    // Use Noto Sans Devanagari to ensure proper glyph coverage for Hindi and the ₹ symbol
  var textTheme = GoogleFonts.notoSansDevanagariTextTheme(base.textTheme).apply();
    textTheme = _normalizeTextTheme(textTheme);
    return base.copyWith(
  textTheme: textTheme,
      primaryTextTheme: _normalizeTextTheme(GoogleFonts.notoSansDevanagariTextTheme(base.primaryTextTheme)),
  typography: Typography.material2021(platform: defaultTargetPlatform),
  pageTransitionsTheme: AppAnimations.pageTransitions,
    // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: textTheme.labelLarge?.copyWith(height: 1.0, leadingDistribution: TextLeadingDistribution.even, textBaseline: TextBaseline.alphabetic),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: textTheme.labelLarge?.copyWith(height: 1.0, leadingDistribution: TextLeadingDistribution.even, textBaseline: TextBaseline.alphabetic),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: textTheme.labelLarge?.copyWith(height: 1.0, leadingDistribution: TextLeadingDistribution.even, textBaseline: TextBaseline.alphabetic),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: textTheme.labelLarge?.copyWith(height: 1.0, leadingDistribution: TextLeadingDistribution.even, textBaseline: TextBaseline.alphabetic),
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: Colors.transparent,
      ),
      // Chips
      chipTheme: base.chipTheme.copyWith(
        labelStyle: textTheme.labelMedium?.copyWith(height: 1.0, leadingDistribution: TextLeadingDistribution.even, textBaseline: TextBaseline.alphabetic),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      ),
      // SearchBar (Material 3)
      searchBarTheme: SearchBarThemeData(
        textStyle: WidgetStatePropertyAll(
          textTheme.bodyLarge?.copyWith(
            height: 1.1,
            leadingDistribution: TextLeadingDistribution.even,
            textBaseline: TextBaseline.alphabetic,
          ),
        ),
        hintStyle: WidgetStatePropertyAll(
          textTheme.bodyLarge
              ?.copyWith(
                height: 1.1,
                leadingDistribution: TextLeadingDistribution.even,
                textBaseline: TextBaseline.alphabetic,
              )
              .copyWith(color: base.colorScheme.onSurfaceVariant),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        ),
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
        prefixIconConstraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        suffixIconConstraints: const BoxConstraints(minHeight: 48, minWidth: 48),
      ),
      floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
  extendedTextStyle: textTheme.labelLarge?.copyWith(height: 1.0, leadingDistribution: TextLeadingDistribution.even, textBaseline: TextBaseline.alphabetic),
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
    final generated = ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark);
    final scheme = generated.copyWith(
      primary: _primary,
      onPrimary: Colors.black, // maintain contrast for elevated/filled buttons in dark theme
    );
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
    // Use Noto Sans Devanagari for consistent dark theme rendering too
  var textTheme = GoogleFonts.notoSansDevanagariTextTheme(base.textTheme).apply(bodyColor: base.colorScheme.onSurface);
    textTheme = _normalizeTextTheme(textTheme);
    return base.copyWith(
      textTheme: textTheme,
      primaryTextTheme: _normalizeTextTheme(GoogleFonts.notoSansDevanagariTextTheme(base.primaryTextTheme)),
  typography: Typography.material2021(platform: defaultTargetPlatform),
  pageTransitionsTheme: AppAnimations.pageTransitions,
    // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: textTheme.labelLarge?.copyWith(height: 1.0, leadingDistribution: TextLeadingDistribution.even, textBaseline: TextBaseline.alphabetic),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: textTheme.labelLarge?.copyWith(height: 1.0, leadingDistribution: TextLeadingDistribution.even, textBaseline: TextBaseline.alphabetic),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: textTheme.labelLarge?.copyWith(height: 1.0, leadingDistribution: TextLeadingDistribution.even, textBaseline: TextBaseline.alphabetic),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: textTheme.labelLarge?.copyWith(height: 1.0, leadingDistribution: TextLeadingDistribution.even, textBaseline: TextBaseline.alphabetic),
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: Colors.transparent,
      ),
      // Chips
      chipTheme: base.chipTheme.copyWith(
        labelStyle: textTheme.labelMedium?.copyWith(height: 1.0, leadingDistribution: TextLeadingDistribution.even, textBaseline: TextBaseline.alphabetic),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      ),
      // SearchBar (Material 3)
      searchBarTheme: SearchBarThemeData(
        textStyle: WidgetStatePropertyAll(
          textTheme.bodyLarge?.copyWith(
            height: 1.1,
            leadingDistribution: TextLeadingDistribution.even,
            textBaseline: TextBaseline.alphabetic,
          ),
        ),
        hintStyle: WidgetStatePropertyAll(
          textTheme.bodyLarge
              ?.copyWith(
                height: 1.1,
                leadingDistribution: TextLeadingDistribution.even,
                textBaseline: TextBaseline.alphabetic,
              )
              .copyWith(color: base.colorScheme.onSurfaceVariant),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        ),
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
        prefixIconConstraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        suffixIconConstraints: const BoxConstraints(minHeight: 48, minWidth: 48),
      ),
      floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
  extendedTextStyle: textTheme.labelLarge?.copyWith(height: 1.0, leadingDistribution: TextLeadingDistribution.even, textBaseline: TextBaseline.alphabetic),
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
