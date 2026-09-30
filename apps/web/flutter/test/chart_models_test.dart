import 'package:flutter_test/flutter_test.dart';
import 'package:chez_yasmine/charts/chart_models.dart';

void main() {
  group('WeeklyChart.total', () {
    test('sums every point across every series', () {
      final chart = WeeklyChart(
        weekStart: '2026-09-14',
        weekEnd: '2026-09-20',
        series: [
          WeeklySeries(
            id: 'c1',
            name: 'Boissons',
            points: [
              WeeklyPoint(day: 'Lundi', value: 1000),
              WeeklyPoint(day: 'Mardi', value: 500),
            ],
          ),
          WeeklySeries(
            id: 'c2',
            name: 'Plats',
            points: [
              WeeklyPoint(day: 'Lundi', value: 2000),
              WeeklyPoint(day: 'Mardi', value: 0),
            ],
          ),
        ],
      );

      expect(chart.total, 3500);
    });

    test('is zero for an empty series list', () {
      final chart = WeeklyChart(weekStart: '', weekEnd: '', series: []);

      expect(chart.total, 0);
    });
  });

  group('MonthlyChart.total (2026-09-25 — badge « Top recettes »/« Top bénéfices »)', () {
    test('sums every month of the year', () {
      final chart = MonthlyChart(
        year: 2026,
        months: [
          MonthlyPoint(month: 'Janvier', value: 100000),
          MonthlyPoint(month: 'Février', value: 50000),
        ],
      );

      expect(chart.total, 150000);
    });

    test('is zero for an empty month list', () {
      final chart = MonthlyChart(year: 2026, months: []);

      expect(chart.total, 0);
    });
  });

  group('RankingChart.fromJson (2026-09-30 — badge « Top dépenses »)', () {
    test('parses total when the backend sends it (Top dépenses)', () {
      final chart = RankingChart.fromJson({
        'from': '2026-01-01T00:00:00.000Z',
        'to': '2026-12-31T23:59:59.000Z',
        'groupBy': 'category',
        'items': [
          {'id': 'Loyer', 'name': 'Loyer', 'value': 50000},
        ],
        'total': 123456,
      });

      expect(chart.total, 123456);
    });

    test('total is null when absent (Top recettes/Top bénéfices, qui ne l\'envoient pas)', () {
      final chart = RankingChart.fromJson({
        'from': '2026-01-01T00:00:00.000Z',
        'to': '2026-12-31T23:59:59.000Z',
        'groupBy': 'product',
        'items': <Map<String, dynamic>>[],
      });

      expect(chart.total, isNull);
    });
  });
}
