import 'package:flutter/material.dart';
import 'package:responsiveness/responsiveness.dart';

/// Central place to read breakpoints and expose sizes.
class R {
  R._();

  static double gutter(BuildContext context) => const ResponsiveValue<double>(
        xs: 8,
        sm: 12,
        md: 16,
        lg: 20,
        xl: 24,
        xxl: 28,
      ).of(context);

  static EdgeInsets pagePadding(BuildContext context) {
    final g = gutter(context);
    return EdgeInsets.all(g);
  }

  static double maxContentWidth(BuildContext context) => const ResponsiveValue<double>(
        xs: 720,
        sm: 820,
        md: 980,
        lg: 1100,
        xl: 1280,
        xxl: 1440,
      ).of(context);

  static bool isCompact(BuildContext context) => ScreenSize.of(context).index <= ScreenSize.sm.index;

  // Additional helpers for very small screens and ultra-compact layouts.
  // Extra-small breakpoint: phones ≤ 420px logical width
  static bool isXSmall420(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return w <= 420;
  }

  // Micro breakpoint: ultra small and legacy phones ≤ 320px logical width
  static bool isMicro320(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return w <= 320;
  }

  // Convenience: very narrow (common cut used across charts/legends)
  static bool isVeryNarrow360(BuildContext context) => MediaQuery.sizeOf(context).width < 360;

  // Common spacing helpers for chips/legends on small screens
  static double chipSpacing(BuildContext context) => isVeryNarrow360(context) ? 3 : 6;
  static double runSpacing(BuildContext context) => isVeryNarrow360(context) ? 3 : 6;

  // Pie chart helpers (center hole radius, section gap, section radius, label font size)
  static double pieCenterSpace(BuildContext context, {required bool small, required bool isAndroid}) {
    final narrow = isVeryNarrow360(context);
    double base = narrow ? 30.0 : (small ? 36.0 : 46.0);
    if (isAndroid && small) base -= 2.0;
    return base;
  }

  static double pieSectionSpace(BuildContext context, {required int sectionCount}) {
    if (isVeryNarrow360(context)) return 4.0; // slightly larger gaps on very narrow screens to reduce overlap
    if (sectionCount > 6 && isXs420(context)) return 3.0;
    return 2.0;
  }

  static double pieSectionRadius(BuildContext context, {required bool small, required bool isAndroid}) {
    final narrow = isVeryNarrow360(context);
    double base = narrow ? 20.0 : (small ? 20.0 : 40.0);
    if (isAndroid && small) base -= 2.0;
    return base;
  }

  static double pieLabelFontSize(BuildContext context, {required bool small}) {
    if (isMicro320(context)) return 6.5;
    if (isVeryNarrow360(context)) return 7.0;
    return small ? 8.8 : 10.5;
  }

  // Backward-compatible alias (was used in some files)
  static bool isXs420(BuildContext context) {
    return isXSmall420(context);
  }
}
