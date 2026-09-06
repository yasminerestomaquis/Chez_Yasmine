import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'chart_models.dart';

/// Courbe des 12 mois (Janvier..Décembre) d'une année, utilisée par
/// "Recettes mensuelles" et "Bénéfices mensuels".
class MonthlyLineChartWidget extends StatelessWidget {
  const MonthlyLineChartWidget({super.key, required this.months, required this.color});

  final List<MonthlyPoint> months;
  final Color color;

  static const _labels = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin', 'Juil', 'Août', 'Sep', 'Oct', 'Nov', 'Déc'];

  @override
  Widget build(BuildContext context) {
    if (months.every((m) => m.value == 0)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('Aucune donnée pour cette année')),
      );
    }
    final maxY = months.map((m) => m.value).fold<double>(0, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY <= 0 ? 1 : maxY * 1.2,
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots
                  .map((s) => LineTooltipItem('${s.y.toStringAsFixed(0)} FCFA', const TextStyle(color: Colors.white, fontSize: 11)))
                  .toList(),
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
                  if (i < 0 || i >= _labels.length) return const SizedBox.shrink();
                  return Padding(padding: const EdgeInsets.only(top: 6), child: Text(_labels[i]));
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < months.length; i++) FlSpot(i.toDouble(), months[i].value)],
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
