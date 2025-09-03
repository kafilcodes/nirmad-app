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
}
