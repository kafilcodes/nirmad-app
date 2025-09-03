import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_messaging/firebase_messaging.dart';

@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  // No-op for now. If needed, initialize Firebase here and process message.
}

class MessagingService {
  MessagingService._();

  static Future<void> init() async {
    final messaging = FirebaseMessaging.instance;

    // Request permissions (required on iOS, Android 13+)
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    // Register background handler
    try {
      FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);
    } catch (_) {
      // In some web contexts without a proper service worker this can throw; ignore.
    }

    // Register token and listen for refresh
    await _registerToken();
    try {
      FirebaseMessaging.instance.onTokenRefresh.listen((t) => _saveToken(t));
    } catch (_) {}

    // Foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // Optionally, handle foreground notifications here (snackbars/overlays).
    });
  }

  static Future<void> _registerToken() async {
    String? token;
    try {
      if (kIsWeb) {
        final vapid = dotenv.maybeGet('FCM_VAPID_KEY');
        token = await FirebaseMessaging.instance.getToken(vapidKey: vapid);
      } else {
        token = await FirebaseMessaging.instance.getToken();
      }
    } catch (_) {
      // Likely due to service worker not being available yet; skip silently.
      token = null;
    }
    if (token != null) {
      await _saveToken(token);
    }
  }

  static Future<void> _saveToken(String token) async {
    final uid = fb.FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('fcmTokens')
        .doc(token);
    await doc.set({
      'token': token,
      'platform': Platform.operatingSystem,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
