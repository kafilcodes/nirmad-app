// Messaging service intentionally left as a no-op to disable push notifications.

class MessagingService {
  MessagingService._();

  static Future<void> init() async {
  // Push notifications disabled: no-op to avoid token registration and extra API calls
  return;
  }
}
