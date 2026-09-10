import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../common/formatting.dart';
import 'chart_models.dart';

/// Histogramme vertical générique pour les graphiques hebdomadaires
/// (Lundi..Dimanche), avec une ou plusieurs séries groupées par jour.
///
/// [baseColor] identifie le *type* de graphique (une couleur différente par
/// graphique, comme demandé) ; quand plusieurs séries sont affichées (par
/// catégorie ou par produit sans filtre), chacune reprend une nuance de
/// [baseColor] plutôt qu'une couleur sans rapport, pour rester dans la même
/// famille visuelle tout en restant distinguable.
class WeeklyBarChartWidget extends StatelessWidget {
  const WeeklyBarChartWidget({super.key, required this.series, required this.baseColor});

  final List<WeeklySeries> series;
  final Color baseColor;

  static const _days = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
  static const _shadeSteps = [0.0, 0.45, 0.2, 0.6, 0.32, 0.75, 0.12];

  Color _shade(int index) => Color.lerp(baseColor, Colors.black, _shadeSteps[index % _shadeSteps.length])!;

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
                        color: _shade(i),
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
                    Container(width: 10, height: 10, color: _shade(i)),
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
