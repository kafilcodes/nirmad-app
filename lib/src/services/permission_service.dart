import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  /// Request the core permissions. Returns true when all granted.
  static Future<bool> requestCorePermissions() async {
    if (kIsWeb) return true; // No runtime prompts on web
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    final req = <Future<PermissionStatus>>[];
    // Notifications (Android 13+)
    req.add(Permission.notification.request());
    // Location when in use
    req.add(Permission.locationWhenInUse.request());
    // Camera for in-app capture
    req.add(Permission.camera.request());
  // No storage permission on Android; we use SAF/file pickers without runtime permission.
    // iOS: explicit media permissions
    if (Platform.isIOS) {
      req.add(Permission.photos.request());
      req.add(Permission.videos.request());
    }
    final statuses = await Future.wait(req);
    return statuses.every((s) => s.isGranted);
  }

  /// Check whether all core permissions are granted without requesting.
  static Future<bool> allGranted() async {
    if (kIsWeb) return true;
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    final checks = <Future<PermissionStatus>>[
      Permission.notification.status,
      Permission.locationWhenInUse.status,
      Permission.camera.status,
    ];
  // Storage not required on Android
    if (Platform.isIOS) {
      checks.add(Permission.photos.status);
      checks.add(Permission.videos.status);
    }
    final statuses = await Future.wait(checks);
    return statuses.every((s) => s.isGranted);
  }

  /// List human-friendly missing permissions for UI messaging.
  static Future<List<String>> missingPermissions() async {
    if (await allGranted()) return const [];
    final missing = <String>[];
    final n = await Permission.notification.status;
    if (!n.isGranted) missing.add('Notifications');
    final loc = await Permission.locationWhenInUse.status;
    if (!loc.isGranted) missing.add('Location');
    final cam = await Permission.camera.status;
    if (!cam.isGranted) missing.add('Camera');
  // No storage permission on Android
    if (Platform.isIOS) {
      final ph = await Permission.photos.status;
      if (!ph.isGranted) missing.add('Photos');
      final vd = await Permission.videos.status;
      if (!vd.isGranted) missing.add('Videos');
    }
    return missing;
  }
}
