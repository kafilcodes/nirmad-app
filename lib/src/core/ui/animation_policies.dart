import 'package:flutter/material.dart';
import 'package:animations/animations.dart';
import 'package:go_transitions/go_transitions.dart';

/// Centralized animation configuration for the app.
class AppAnimations {
  AppAnimations._();

  // Page transitions: set platform-appropriate defaults using GoTransitions
  static final pageTransitions = PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: GoTransitions.fadeUpwards,
      TargetPlatform.iOS: GoTransitions.cupertino,
      TargetPlatform.macOS: GoTransitions.cupertino,
      TargetPlatform.windows: GoTransitions.fadeUpwards,
      TargetPlatform.linux: GoTransitions.fadeUpwards,
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
