import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:toastification/toastification.dart';

/// Compact, floating toast used across the app (wraps toastification).
void showToast(
  BuildContext context,
  String message, {
  IconData icon = CupertinoIcons.info,
  bool error = false,
  double width = 380, // kept for backward compat; not used by toastification
}) {
  toastification.show(
    context: context,
    title: Text(message),
    type: error ? ToastificationType.error : ToastificationType.info,
    style: ToastificationStyle.fillColored,
    autoCloseDuration: const Duration(seconds: 3),
    showProgressBar: false,
    icon: Icon(icon),
  );
}
