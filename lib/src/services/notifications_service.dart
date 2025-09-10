// Notifications service disabled; keep API no-ops to avoid breaking imports.
class NotificationsService {
  NotificationsService();

  Future<void> initialize() async {
    // No-op
  }

  Future<void> subscribeUser(String userId) async {}
  Future<void> unsubscribeUser(String userId) async {}
  Future<void> subscribeBlock(String blockId) async {}
  Future<void> unsubscribeBlock(String blockId) async {}
}
