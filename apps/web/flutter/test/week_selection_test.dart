import 'package:flutter_test/flutter_test.dart';

import 'package:chez_yasmine/charts/chart_models.dart';
import 'package:chez_yasmine/charts/week_selection.dart';

WeeklyChart _chart(String weekStart, String weekEnd, List<WeeklySeries> series) =>
    WeeklyChart(weekStart: weekStart, weekEnd: weekEnd, series: series);

WeeklySeries _series(String? id, String name, List<double> values) => WeeklySeries(
      id: id,
      name: name,
      points: [
        for (var i = 0; i < values.length; i++) WeeklyPoint(day: 'day$i', value: values[i]),
      ],
    );

void main() {
  group('mondayOfWeek (2026-09-24)', () {
    test('ramène nimporte quel jour de la semaine à son lundi', () {
      // Jeudi 24/09/2026 -> lundi 21/09/2026.
      expect(mondayOfWeek(DateTime(2026, 9, 24)), DateTime(2026, 9, 21));
      // Un lundi reste lui-même.
      expect(mondayOfWeek(DateTime(2026, 9, 21)), DateTime(2026, 9, 21));
      // Dimanche 27/09/2026 -> lundi 21/09/2026 (même semaine ISO).
      expect(mondayOfWeek(DateTime(2026, 9, 27)), DateTime(2026, 9, 21));
    });
  });

  group('weekFilterLabel', () {
    test('« Choisir la semaine » pour 0 ou 1 semaine sélectionnée', () {
      expect(weekFilterLabel({}), 'Choisir la semaine');
      expect(weekFilterLabel({DateTime(2026, 9, 21)}), 'Choisir la semaine');
    });

    test('« N semaines sélectionnées » au-delà dune semaine', () {
      expect(weekFilterLabel({DateTime(2026, 9, 21), DateTime(2026, 9, 14)}), '2 semaines sélectionnées');
    });
  });

  group('mergeWeeklyCharts (sélection multiple de semaines, 2026-09-24)', () {
    test('additionne les points jour par jour, même série présente dans chaque semaine', () {
      final week1 = _chart('2026-09-14', '2026-09-20', [_series('p1', 'Bière', [10, 0, 0, 0, 0, 0, 0])]);
      final week2 = _chart('2026-09-21', '2026-09-27', [_series('p1', 'Bière', [5, 0, 0, 0, 0, 0, 0])]);

      final merged = mergeWeeklyCharts([week1, week2]);

      expect(merged.series, hasLength(1));
      expect(merged.series.first.points.first.value, 15);
      expect(merged.total, 15);
    });

    test('fusionne par identifiant : une série absente dune semaine ny contribue simplement pas', () {
      final week1 = _chart('2026-09-14', '2026-09-20', [_series('p1', 'Bière', [10, 0, 0, 0, 0, 0, 0])]);
      final week2 = _chart('2026-09-21', '2026-09-27', [_series('p2', 'Soda', [3, 0, 0, 0, 0, 0, 0])]);

      final merged = mergeWeeklyCharts([week1, week2]);

      expect(merged.series.map((s) => s.name), containsAll(['Bière', 'Soda']));
      expect(merged.total, 13);
    });

    test('retrie les séries fusionnées par total décroissant', () {
      final week1 = _chart('2026-09-14', '2026-09-20', [
        _series('p1', 'Bière', [1, 0, 0, 0, 0, 0, 0]),
        _series('p2', 'Soda', [2, 0, 0, 0, 0, 0, 0]),
      ]);
      final week2 = _chart('2026-09-21', '2026-09-27', [
        _series('p1', 'Bière', [10, 0, 0, 0, 0, 0, 0]),
      ]);

      final merged = mergeWeeklyCharts([week1, week2]);

      expect(merged.series.first.name, 'Bière');
    });

    test('weekStart/weekEnd du résultat couvrent la première et la dernière semaine', () {
      final week1 = _chart('2026-09-21', '2026-09-27', [_series(null, 'Total', List.filled(7, 0))]);
      final week2 = _chart('2026-09-07', '2026-09-13', [_series(null, 'Total', List.filled(7, 0))]);

      final merged = mergeWeeklyCharts([week1, week2]);

      expect(merged.weekStart, '2026-09-07');
      expect(merged.weekEnd, '2026-09-27');
    });

    test('refuse une liste vide', () {
      expect(() => mergeWeeklyCharts([]), throwsArgumentError);
    });
  });

  group('realizedWeeksSince (graphique "Recettes des semaines", 2026-09-25)', () {
    test('weeklyRevenueTrendAnchor est bien le lundi 14/09/2026 (S1)', () {
      expect(weeklyRevenueTrendAnchor, DateTime(2026, 9, 14));
      expect(mondayOfWeek(weeklyRevenueTrendAnchor), weeklyRevenueTrendAnchor);
    });

    test('une seule semaine (S1) quand "maintenant" tombe dans la semaine de l\'ancre', () {
      final weeks = realizedWeeksSince(DateTime(2026, 9, 14), DateTime(2026, 9, 18));
      expect(weeks, [DateTime(2026, 9, 14)]);
    });

    test('énumère chaque lundi jusqu\'à la semaine courante incluse, dans l\'ordre', () {
      // 01/10/2026 (jeudi) tombe dans la semaine du 28/09 au 04/10 -> S3.
      final weeks = realizedWeeksSince(DateTime(2026, 9, 14), DateTime(2026, 10, 1));
      expect(weeks, [DateTime(2026, 9, 14), DateTime(2026, 9, 21), DateTime(2026, 9, 28)]);
    });

    test('ramène "maintenant" à son propre lundi avant de comparer, pas seulement l\'ancre', () {
      // "now" un dimanche doit quand même inclure la semaine en cours entière.
      final weeks = realizedWeeksSince(DateTime(2026, 9, 14), DateTime(2026, 9, 20));
      expect(weeks, [DateTime(2026, 9, 14)]);
    });

    test('weekTrendLabel produit S1, S2, S3...', () {
      expect(weekTrendLabel(1), 'S1');
      expect(weekTrendLabel(12), 'S12');
    });
  });
}
