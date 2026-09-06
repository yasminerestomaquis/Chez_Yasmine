import 'package:flutter/material.dart';

import 'chart_models.dart';

/// Classement horizontal (le plus lisible pour des noms de catégories/produits
/// de longueur variable) utilisé par "Top recettes" et "Top bénéfices" — les
/// deux seuls graphiques de ce module qui ne sont pas décrits comme des
/// histogrammes verticaux dans la demande.
class RankingBarChartWidget extends StatelessWidget {
  const RankingBarChartWidget({super.key, required this.items, required this.color});

  final List<RankingItem> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('Aucune donnée pour cette période')),
      );
    }
    final maxValue = items.map((i) => i.value).fold<double>(0, (a, b) => a > b ? a : b);

    return Column(
      children: [
        for (var rank = 0; rank < items.length; rank++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(width: 20, child: Text('${rank + 1}', style: const TextStyle(fontWeight: FontWeight.bold))),
                SizedBox(
                  width: 110,
                  child: Text(items[rank].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final ratio = maxValue <= 0 ? 0.0 : (items[rank].value / maxValue).clamp(0.02, 1.0);
                      return Stack(
                        children: [
                          Container(height: 18, decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4))),
                          Container(
                            width: constraints.maxWidth * ratio,
                            height: 18,
                            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  child: Text(
                    '${items[rank].value.toStringAsFixed(0)} FCFA',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
