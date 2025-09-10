import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

/// Compact, floating toast used across the app (wraps toastification).
void showToast(
  BuildContext context,
  String message, {
  IconData icon = CupertinoIcons.info,
  bool error = false,
  double width = 380, // kept for backward compat; not used by toastification
}) {
  final cs = Theme.of(context).colorScheme;
  final type = error ? ToastificationType.error : ToastificationType.success;
  toastification.show(
    context: context,
    type: type,
    style: ToastificationStyle.flat,
    autoCloseDuration: const Duration(seconds: 3),
    showProgressBar: false,
    title: Text(message, style: TextStyle(color: error ? cs.onError : cs.onPrimary)),
    backgroundColor: error ? cs.error : cs.primary,
    icon: Icon(icon, color: error ? cs.onError : cs.onPrimary),
  );
}
