import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// A tooltip that triggers on hover for desktop/web and on long-press for touch devices.
class HybridTooltip extends StatelessWidget {
  const HybridTooltip({
    super.key,
    required this.message,
    required this.child,
    this.preferBelow,
    this.waitDuration,
    this.showDuration,
  });

  final String message;
  final Widget child;
  final bool? preferBelow;
  final Duration? waitDuration;
  final Duration? showDuration;

  bool _isDesktop(TargetPlatform platform) {
    return platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux;
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final isTouchContext = !kIsWeb && !_isDesktop(platform);

    // On desktop/web, Tooltip shows on hover by default; on touch we prefer long-press.
    if (isTouchContext) {
      return Tooltip(
        message: message,
        preferBelow: preferBelow,
        waitDuration: waitDuration ?? const Duration(milliseconds: 300),
        showDuration: showDuration ?? const Duration(seconds: 6),
        triggerMode: TooltipTriggerMode.longPress,
        child: child,
      );
    }

    return Tooltip(
      message: message,
      preferBelow: preferBelow,
      waitDuration: waitDuration ?? const Duration(milliseconds: 150),
      showDuration: showDuration ?? const Duration(seconds: 6),
      // Don't set triggerMode here so hover works as expected on desktop/web
      child: child,
    );
  }
}