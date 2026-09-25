import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../common/formatting.dart';

/// Courbe « Recettes des semaines » (onglet Recettes — demande utilisateur
/// du 2026-09-25) : une recette totale par semaine réalisée depuis S1
/// (`realizedWeeksSince`, `week_selection.dart`), axe des x en S1/S2/S3...
///
/// [weekTotals] est indexé comme la liste complète des semaines réalisées
/// (position 0 = S1, fixe) ; [selected] ne retient, pour l'affichage, que
/// les indices cochés dans le filtre multi-semaines — une semaine
/// désélectionnée laisse un trou dans la courbe plutôt que de renuméroter
/// les suivantes, pour que « S3 » désigne toujours la même semaine calendaire
/// quelle que soit la sélection courante.
class WeeklyRevenueTrendChartWidget extends StatelessWidget {
  const WeeklyRevenueTrendChartWidget({
    super.key,
    required this.weekTotals,
    required this.selected,
    required this.color,
  });

  final List<double> weekTotals;
  final Set<int> selected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (var i = 0; i < weekTotals.length; i++)
        if (selected.contains(i)) FlSpot(i.toDouble(), weekTotals[i]),
    ];
    if (spots.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('Aucune semaine sélectionnée')),
      );
    }
    final maxY = weekTotals.fold<double>(0, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (weekTotals.length - 1).toDouble(),
          minY: 0,
          maxY: maxY <= 0 ? 1 : maxY * 1.2,
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touched) => [
                for (final s in touched)
                  LineTooltipItem(
                    'S${s.x.toInt() + 1}\n${formatAmount(s.y)} FCFA',
                    const TextStyle(color: Colors.white, fontSize: 11),
                  ),
              ],
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 48)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= weekTotals.length) return const SizedBox.shrink();
                  return Padding(padding: const EdgeInsets.only(top: 6), child: Text('S${i + 1}'));
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: color,
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.15)),
            ),
          ],
        ),
      ),
    );
  }
}
