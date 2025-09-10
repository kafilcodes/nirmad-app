import 'package:flutter/material.dart';

/// 1rem = 16 logical pixels. Use for typography sizing guidance.
double rem(double units) => units * 16.0;

/// Line-height helpers for readability on small text.
double lhTight(BuildContext context) => 1.2;
double lhNormal(BuildContext context) => 1.35;
double lhRelaxed(BuildContext context) => 1.5;

/// Common paddings based on the project responsive gutter.
class UX {
  UX._();
  static const double base = 8; // 0.5rem
  static EdgeInsets sectionPad(BuildContext _) => const EdgeInsets.all(base * 2);
  static EdgeInsets cardPad(BuildContext _) => const EdgeInsets.all(base * 1.5);
}
