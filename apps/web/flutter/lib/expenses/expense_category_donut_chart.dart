import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../common/formatting.dart';
import '../theme/app_theme.dart';
import 'expense_summary_models.dart';

const _paletteColors = [
  AppColors.green,
  AppColors.orange,
  Color(0xFF3B82F6),
  Color(0xFFA855F7),
  Color(0xFFEAB308),
  AppColors.alert,
  Color(0xFF14B8A6),
  Color(0xFF6B7280),
];

/// Répartition des dépenses par nature (Vue d'ensemble) — anneau via
/// `fl_chart` (déjà en dépendance, `PieChart`), avec légende manuelle
/// (montant + pourcentage), pas de camembert/anneau réutilisable ailleurs
/// dans l'app à ce jour.
class ExpenseCategoryDonutChart extends StatelessWidget {
  const ExpenseCategoryDonutChart({super.key, required this.items});

  final List<ExpenseCategoryAmount> items;

  @override
  Widget build(BuildContext context) {
    final total = items.fold<double>(0, (sum, i) => sum + i.amount);
    if (items.isEmpty || total <= 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('Aucune donnée pour cette période')),
      );
    }
    final sorted = [...items]..sort((a, b) => b.amount.compareTo(a.amount));

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 48,
              sections: [
                for (var i = 0; i < sorted.length; i++)
                  PieChartSectionData(
                    value: sorted[i].amount,
                    color: _paletteColors[i % _paletteColors.length],
                    title: '',
                    radius: 36,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < sorted.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  color: _paletteColors[i % _paletteColors.length],
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(sorted[i].category)),
                Text(
                  '${formatAmount(sorted[i].amount)} FCFA — '
                  '${(sorted[i].amount / total * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
