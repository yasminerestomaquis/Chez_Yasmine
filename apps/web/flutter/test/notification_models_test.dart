import 'package:flutter_test/flutter_test.dart';
import 'package:chez_yasmine/notifications/notification_models.dart';

void main() {
  group('AppNotification.fromJson', () {
    test('parses createdByName when present (traçabilité, 2026-09-13)', () {
      final notification = AppNotification.fromJson({
        'id': 'notif-1',
        'title': 'Nouvelle vente',
        'createdAt': '2026-09-13T10:00:00.000Z',
        'createdByName': 'Awa Koné',
      });

      expect(notification.createdByName, 'Awa Koné');
    });

    test('defaults createdByName to null when absent (ex. alerte de stock bas, sans auteur humain)', () {
      final notification = AppNotification.fromJson({
        'id': 'notif-2',
        'title': 'Stock bas : Bière',
        'createdAt': '2026-09-13T10:00:00.000Z',
      });

      expect(notification.createdByName, isNull);
    });
  });
}
