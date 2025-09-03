import 'package:flutter/material.dart';

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
              const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2)),
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
