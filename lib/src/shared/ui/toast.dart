import 'package:flutter/material.dart';

/// Compact, floating toast/snackbar used across the app.
void showToast(BuildContext context, String message, {IconData icon = Icons.info_outline, bool error = false, double width = 380}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(children:[Icon(icon, size: 18), const SizedBox(width: 8), Expanded(child: Text(message))]),
      behavior: SnackBarBehavior.floating,
      width: width,
      backgroundColor: error ? Colors.red.withOpacity(0.9) : null,
    ),
  );
}
