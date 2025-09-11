import 'package:flutter/material.dart';

/// A reusable scroll-safe dialog wrapper to avoid overflow on small devices.
/// Usage: showDialog(... builder: (_) => ScrollSafeDialog(child: Column(...)) )
class ScrollSafeDialog extends StatelessWidget {
  const ScrollSafeDialog({super.key, required this.child, this.maxWidth = 520});
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (c, constraints) {
        final maxW = constraints.maxWidth;
        final targetW = maxW < maxWidth ? (maxW * 0.94) : maxWidth;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: targetW,
              maxHeight: constraints.maxHeight * 0.90,
            ),
            child: Material(
              type: MaterialType.card,
              elevation: 8,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<T?> showScrollSafeDialog<T>({required BuildContext context, required WidgetBuilder builder, bool barrierDismissible = true}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => ScrollSafeDialog(child: builder(ctx)),
  );
}
