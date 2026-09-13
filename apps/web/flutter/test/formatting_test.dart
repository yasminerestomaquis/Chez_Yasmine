import 'package:flutter_test/flutter_test.dart';
import 'package:chez_yasmine/common/formatting.dart';

void main() {
  group('formatRelativeTime', () {
    test('says "à l\'instant" for less than a minute ago', () {
      final since = DateTime.now().subtract(const Duration(seconds: 10));
      expect(formatRelativeTime(since), "à l'instant");
    });

    test('formats minutes, singular and plural', () {
      expect(
        formatRelativeTime(DateTime.now().subtract(const Duration(minutes: 1))),
        'il y a 1 minute',
      );
      expect(
        formatRelativeTime(DateTime.now().subtract(const Duration(minutes: 5))),
        'il y a 5 minutes',
      );
    });

    test('formats hours once past 60 minutes', () {
      expect(
        formatRelativeTime(DateTime.now().subtract(const Duration(hours: 2))),
        'il y a 2 heures',
      );
    });

    test('formats days once past 24 hours', () {
      expect(
        formatRelativeTime(DateTime.now().subtract(const Duration(days: 3))),
        'il y a 3 jours',
      );
    });
  });
}
