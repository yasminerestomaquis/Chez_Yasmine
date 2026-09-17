import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../common/formatting.dart';
import 'chart_models.dart';

/// Total de la semaine affichée, en haut à droite d'un graphique
/// hebdomadaire (Recettes/Dépenses journalières, avec ou sans filtre
/// catégorie) — demande utilisateur du 2026-09-17.
class WeekTotalBadge extends StatelessWidget {
  const WeekTotalBadge({super.key, required this.total, required this.color});

  final double total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topRight,
      child: Text(
        '${formatAmount(total)} FCFA',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color),
      ),
    );
  }
}

/// Histogramme vertical générique pour les graphiques hebdomadaires
/// (Lundi..Dimanche), avec une ou plusieurs séries groupées par jour.
///
/// [baseColor] identifie le *type* de graphique (une couleur différente par
/// graphique, comme demandé) et sert de seule couleur quand il n'y a qu'une
/// série. Dès que plusieurs séries sont affichées (par catégorie ou par
/// produit sans filtre), on bascule sur [_categoricalPalette] : nuancer
/// [baseColor] par simple mélange vers le noir donnait des barres trop
/// proches visuellement dès 4-5 catégories (constaté par l'utilisateur,
/// 2026-09-17) — une vraie palette qualitative (teintes distinctes, pas de
/// simple variation de luminosité) reste distinguable quel que soit le
/// nombre de catégories.
class WeeklyBarChartWidget extends StatelessWidget {
  const WeeklyBarChartWidget({super.key, required this.series, required this.baseColor});

  final List<WeeklySeries> series;
  final Color baseColor;

  static const _days = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

  static const _categoricalPalette = [
    Color(0xFF1E88E5), // bleu
    Color(0xFFD81B60), // rose/magenta
    Color(0xFF43A047), // vert
    Color(0xFFFB8C00), // orange
    Color(0xFF8E24AA), // violet
    Color(0xFF00ACC1), // cyan
    Color(0xFFC62828), // rouge
    Color(0xFF6D4C41), // brun
    Color(0xFFFDD835), // jaune
    Color(0xFF3949AB), // indigo
    Color(0xFF00897B), // teal
    Color(0xFFEC407A), // rose clair
  ];

  Color _colorFor(int index) =>
      series.length > 1 ? _categoricalPalette[index % _categoricalPalette.length] : baseColor;

  @override
  Widget build(BuildContext context) {
    final hasData = series.isNotEmpty && series.any((s) => s.points.any((p) => p.value != 0));
    if (!hasData) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('Aucune donnée pour cette semaine')),
      );
    }

    final maxY = series.expand((s) => s.points).map((p) => p.value).fold<double>(0, (a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 220,
          child: BarChart(
            BarChartData(
              maxY: maxY <= 0 ? 1 : maxY * 1.2,
              alignment: BarChartAlignment.spaceAround,
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                    '${series.length > rodIndex ? series[rodIndex].name : ''}\n${formatAmount(rod.toY)} FCFA',
                    const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 48)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= _days.length) return const SizedBox.shrink();
                      return Padding(padding: const EdgeInsets.only(top: 6), child: Text(_days[i]));
                    },
                  ),
                ),
              ),
              barGroups: List.generate(7, (dayIndex) {
                return BarChartGroupData(
                  x: dayIndex,
                  barsSpace: 3,
                  barRods: [
                    for (var i = 0; i < series.length; i++)
                      BarChartRodData(
                        toY: series[i].points[dayIndex].value,
                        color: _colorFor(i),
                        width: series.length > 1 ? 10 : 20,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                  ],
                );
              }),
            ),
          ),
        ),
        if (series.length > 1) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (var i = 0; i < series.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 10, height: 10, color: _colorFor(i)),
                    const SizedBox(width: 4),
                    Text(series[i].name, style: const TextStyle(fontSize: 12)),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}
