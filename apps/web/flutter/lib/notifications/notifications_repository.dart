import '../api/api_client.dart';
import 'notification_models.dart';

/// Correspond à apps/api/nestjs/src/notifications/notifications.controller.ts.
class NotificationsRepository {
  NotificationsRepository(this._api, this.establishmentId);

  final ApiClient _api;
  final String establishmentId;

  String get _base => '/establishments/$establishmentId/notifications';

  Future<List<AppNotification>> listNotifications() async {
    final json = await _api.get(_base) as List<dynamic>;
    return json
        .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<int> unreadCount() async {
    return await _api.get('$_base/unread-count') as int;
  }

  Future<void> markAsRead(String notificationId) {
    return _api.patch('$_base/$notificationId/read');
  }

  Future<void> broadcast({required String title, String? body}) {
    return _api.post('$_base/broadcast', body: {'title': title, 'body': ?body});
  }

  Future<void> checkLowStock() {
    return _api.post('$_base/low-stock-check');
  }

  /// Réservé côté serveur au Super Administrateur (`notifications.manage`) —
  /// efface toutes les notifications de l'organisation, pas seulement
  /// celles de l'appelant.
  Future<void> clearAll() {
    return _api.delete(_base);
  }
}
