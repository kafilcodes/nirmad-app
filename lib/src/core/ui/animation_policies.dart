import 'package:flutter/material.dart';
import 'package:animations/animations.dart';

/// Centralized animation configuration for the app.
class AppAnimations {
  AppAnimations._();

  // Page transitions: prefer FadeThrough for lateral, SharedAxis for nested.
  static const pageTransitions = PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: FadeThroughPageTransitionsBuilder(),
      TargetPlatform.iOS: FadeThroughPageTransitionsBuilder(),
      TargetPlatform.macOS: FadeThroughPageTransitionsBuilder(),
      TargetPlatform.windows: FadeThroughPageTransitionsBuilder(),
      TargetPlatform.linux: FadeThroughPageTransitionsBuilder(),
    },
  );

  // Helper transition builder for in-place child swaps (lists, tab contents, stepper panes)
  static Widget fadeThroughSwap({required Widget child}) => PageTransitionSwitcher(
        duration: const Duration(milliseconds: 250),
        reverse: false,
        transitionBuilder: (child, primary, secondary) => FadeThroughTransition(
          animation: primary,
          secondaryAnimation: secondary,
          child: child,
        ),
        child: child,
      );

  // Shared axis y for vertical steppers and list/detail.
  static PageTransitionsBuilder get sharedAxisY => const SharedAxisPageTransitionsBuilder(
        transitionType: SharedAxisTransitionType.vertical,
      );
}
