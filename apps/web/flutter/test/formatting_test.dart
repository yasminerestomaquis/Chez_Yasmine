import 'package:flutter_test/flutter_test.dart';
import 'package:chez_yasmine/common/formatting.dart';

void main() {
  group('formatDecimalAmount', () {
    test('formats with 2 decimals and a French comma', () {
      expect(formatDecimalAmount(100), '100,00');
      expect(formatDecimalAmount(0.03), '0,03');
    });

    test('separates thousands like formatAmount', () {
      expect(formatDecimalAmount(3333.333333), '3 333,33');
    });

    test('carries the rounding into the integer part', () {
      // 3333.999 arrondi à 2 décimales doit devenir 3334,00, pas 3333,00
      // (piège d'une implémentation en floor(valeur) + reste arrondi).
      expect(formatDecimalAmount(3333.999), '3 334,00');
    });

    test('keeps the minus sign in front of the whole result', () {
      expect(formatDecimalAmount(-2.5), '-2,50');
    });
  });

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
