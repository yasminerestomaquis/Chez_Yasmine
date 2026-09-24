import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'chart_models.dart';

/// Lundi de la semaine ISO contenant [date] — sert de clé de dédoublonnage
/// pour la sélection multiple de semaines (deux dates de la même semaine ne
/// comptent qu'une fois), même semaine que `mondayOf` côté serveur
/// (`ChartsService`) — demande utilisateur du 2026-09-24, filtre « Choisir
/// la semaine » du module Graphiques.
DateTime mondayOfWeek(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  return d.subtract(Duration(days: d.weekday - 1));
}

/// Libellé du bouton « Choisir la semaine » : la semaine unique choisie
/// (bouton lui-même, inchangé), ou le nombre de semaines sélectionnées.
String weekFilterLabel(Set<DateTime> weeks) => weeks.length <= 1 ? 'Choisir la semaine' : '${weeks.length} semaines sélectionnées';

/// Somme, jour de semaine par jour de semaine (Lundi..Dimanche), des
/// graphiques hebdomadaires de chaque semaine sélectionnée — le serveur ne
/// résout qu'une semaine à la fois (`weekStart`), donc une sélection de
/// plusieurs semaines se calcule côté client, même principe que
/// `mergeBreakdowns` (lib/home/date_selection.dart) pour le filtre Date de
/// l'Accueil. Les séries sont fusionnées par identifiant (catégorie/produit/
/// "Total"), puis retriées par total décroissant — même convention que
/// `ChartsService` pour une semaine seule.
WeeklyChart mergeWeeklyCharts(List<WeeklyChart> charts) {
  if (charts.isEmpty) {
    throw ArgumentError('mergeWeeklyCharts: au moins une semaine requise');
  }
  final order = <String>[];
  final byKey = <String, WeeklySeries>{};
  for (final chart in charts) {
    for (final series in chart.series) {
      final key = series.id ?? series.name;
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = WeeklySeries(
          id: series.id,
          name: series.name,
          points: [for (final p in series.points) WeeklyPoint(day: p.day, value: p.value)],
        );
        order.add(key);
      } else {
        for (var i = 0; i < existing.points.length && i < series.points.length; i++) {
          existing.points[i] = WeeklyPoint(day: existing.points[i].day, value: existing.points[i].value + series.points[i].value);
        }
      }
    }
  }
  double totalOf(WeeklySeries s) => s.points.fold(0.0, (sum, p) => sum + p.value);
  final mergedSeries = [for (final key in order) byKey[key]!]..sort((a, b) => totalOf(b).compareTo(totalOf(a)));
  final sortedByStart = [...charts]..sort((a, b) => a.weekStart.compareTo(b.weekStart));
  return WeeklyChart(
    weekStart: sortedByStart.first.weekStart,
    weekEnd: sortedByStart.last.weekEnd,
    series: mergedSeries,
  );
}

/// Dialogue de sélection multiple de semaines : chaque semaine cochée
/// s'affiche en puce retirable, « Ajouter une semaine » ouvre le
/// sélecteur de date natif (dont le jour choisi est ramené à son lundi),
/// « Réinitialiser » revient à la semaine courante seule. Retourne `null` si
/// annulé, sinon l'ensemble final (jamais vide : réinitialise plutôt que de
/// vider complètement, un graphique hebdomadaire exige au moins une semaine).
Future<Set<DateTime>?> pickWeeks(
  BuildContext context, {
  required Set<DateTime> selected,
  required int year,
}) {
  final dayFormat = DateFormat('dd/MM/yyyy');
  var working = Set<DateTime>.from(selected);
  final defaultWeek = mondayOfWeek(_clampToYear(DateTime.now(), year));

  return showDialog<Set<DateTime>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        Future<void> addWeek() async {
          final picked = await showDatePicker(
            context: dialogContext,
            initialDate: working.isEmpty ? defaultWeek : working.last,
            firstDate: DateTime(year, 1, 1),
            lastDate: DateTime(year, 12, 31),
            helpText: 'Choisir un jour de la semaine à ajouter',
          );
          if (picked == null) return;
          setDialogState(() => working.add(mondayOfWeek(picked)));
        }

        final sortedWeeks = working.toList()..sort();
        return AlertDialog(
          title: const Text('Choisir la ou les semaines'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (sortedWeeks.isEmpty)
                  const Text('Aucune semaine sélectionnée.')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final week in sortedWeeks)
                        Chip(
                          label: Text('Semaine du ${dayFormat.format(week)}'),
                          onDeleted: () => setDialogState(() => working.remove(week)),
                        ),
                    ],
                  ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: addWeek,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Ajouter une semaine'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => setDialogState(() => working = {defaultWeek}),
              child: const Text('Réinitialiser'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(working.isEmpty ? {defaultWeek} : working),
              child: const Text('Appliquer'),
            ),
          ],
        );
      },
    ),
  );
}

DateTime _clampToYear(DateTime date, int year) {
  if (date.year == year) return date;
  final now = DateTime.now();
  return now.year == year ? now : DateTime(year, 1, 15);
}
