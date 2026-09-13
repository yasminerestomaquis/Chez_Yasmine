import 'package:flutter_test/flutter_test.dart';
import 'package:chez_yasmine/users/user_models.dart';

void main() {
  group('TeamMember.fromJson', () {
    test('parses email, isOnline and lastSeenAt when present', () {
      final member = TeamMember.fromJson({
        'id': 'membership-1',
        'userId': 'user-1',
        'user': {
          'fullName': 'Awa',
          'email': 'awa@example.com',
          'isOnline': true,
          'lastSeenAt': '2026-09-13T07:00:00.000Z',
        },
        'role': {'id': 'role-1', 'name': 'Serveur'},
      });

      expect(member.email, 'awa@example.com');
      expect(member.isOnline, true);
      expect(member.lastSeenAt, DateTime.parse('2026-09-13T07:00:00.000Z'));
    });

    test(
      'defaults isOnline to false and email/lastSeenAt to null when absent',
      () {
        final member = TeamMember.fromJson({
          'id': 'membership-2',
          'userId': 'user-2',
          'user': {'fullName': 'Koffi'},
          'role': {'id': 'role-2', 'name': 'Caissier'},
        });

        expect(member.email, isNull);
        expect(member.isOnline, false);
        expect(member.lastSeenAt, isNull);
      },
    );
  });
}
