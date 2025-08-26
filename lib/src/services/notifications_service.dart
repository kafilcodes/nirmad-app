import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationsService {
  final FirebaseMessaging _messaging;
  NotificationsService(this._messaging);

  Future<void> initialize() async {
    if (Platform.isIOS || Platform.isMacOS) {
      await _messaging.requestPermission(alert: true, badge: true, sound: true);
    }
    await _messaging.setAutoInitEnabled(true);
  }

  Future<void> subscribeUser(String userId) => _messaging.subscribeToTopic('user_$userId');
  Future<void> unsubscribeUser(String userId) => _messaging.unsubscribeFromTopic('user_$userId');
  Future<void> subscribeBlock(String blockId) => _messaging.subscribeToTopic('block_$blockId');
  Future<void> unsubscribeBlock(String blockId) => _messaging.unsubscribeFromTopic('block_$blockId');
}
