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
}
