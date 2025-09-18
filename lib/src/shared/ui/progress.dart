import 'package:flutter/material.dart';
import 'package:load_it/load_it.dart';
import 'package:nirmadapp/src/core/ui/responsive_policies.dart';

enum AppLoadingVariant { inline, page, overlay }

class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({
    super.key,
    this.size = 20,
    this.strokeWidth = 2.0,
    this.color,
    this.backgroundColor,
    this.variant = AppLoadingVariant.inline,
  });

  final double size;
  final double strokeWidth; // kept for API compatibility; unused by FlipDotsIndicator
  final Color? color;
  final Color? backgroundColor; // kept for API compatibility; applied via DecoratedBox
  final AppLoadingVariant variant;

  double _resolveSize(BuildContext context) {
    switch (variant) {
      case AppLoadingVariant.inline:
        // Maintain backward compatibility: keep provided size for inline usage
        return size;
      case AppLoadingVariant.page:
        // Larger indicator for full-page loading states
        return R.isCompact(context) ? 28 : 36;
      case AppLoadingVariant.overlay:
        // Slightly smaller than page, suitable for dialogs/overlays
        return R.isCompact(context) ? 24 : 28;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color? fg = color;
    final Color dotColor = fg ?? Theme.of(context).colorScheme.primary;

    final double effSize = _resolveSize(context);

    Widget indicator = FlipDotsIndicator(
      color: dotColor,
      size: effSize,
    );

    if (backgroundColor != null) {
      indicator = DecoratedBox(
        decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
        child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: indicator,
        ),
      );
    }

    return SizedBox(height: effSize, width: effSize, child: Center(child: indicator));
  }
}

Future<void> showBlockingProgress(BuildContext context, {String message = 'Please wait…'}) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 64),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLoadingIndicator(variant: AppLoadingVariant.overlay),
              const SizedBox(width: 12),
              Flexible(child: Text(message)),
            ],
          ),
        ),
      ),
    ),
  );
}

void hideBlockingProgress(BuildContext context) {
  Navigator.of(context, rootNavigator: true).maybePop();
}
