import 'package:flutter/material.dart';

import 'expense_charts_tab.dart';
import 'metric_charts_tab.dart';
import 'stock_lots_tab.dart';

/// Module "Graphiques" : quatre sous-modules (Recettes, Bénéfices, Stock,
/// Dépenses). Recettes et Bénéfices comptent chacun 5 graphiques (voir
/// `MetricChartsTab`) pilotés par le filtre Année de cette page. Dépenses
/// (voir `ExpenseChartsTab`) en compte 4 — pas de "par produit", une dépense
/// n'étant rattachée à aucun produit — et suit le même filtre Année. Stock
/// (voir `StockLotsTab`) est le seul exclu de ce filtre : c'est une fiche de
/// lots FIFO représentant l'état courant du stock, pas une période.
class GraphiquesPage extends StatefulWidget {
  const GraphiquesPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<GraphiquesPage> createState() => _GraphiquesPageState();
}

class _GraphiquesPageState extends State<GraphiquesPage> {
  late int _year = DateTime.now().year;

  static const _recettesTitles = ChartTitles(
    dailyTotal: 'Recettes journalières totales',
    dailyByCategory: 'Recettes journalières totales par catégorie',
    dailyByProduct: 'Recettes journalières totales par produit',
    top: 'Top recettes',
    monthly: 'Recettes mensuelles',
  );

  static const _recettesPalette = ChartPalette(
    dailyTotal: Colors.blue,
    dailyByCategory: Colors.teal,
    dailyByProduct: Colors.indigo,
    top: Colors.green,
    monthly: Colors.deepOrange,
  );

  static const _beneficesTitles = ChartTitles(
    dailyTotal: 'Bénéfices journaliers totaux',
    dailyByCategory: 'Bénéfices journaliers totaux par catégorie',
    dailyByProduct: 'Bénéfices journaliers totaux par produit',
    top: 'Top bénéfices',
    monthly: 'Bénéfices mensuels',
  );

  static const _beneficesPalette = ChartPalette(
    dailyTotal: Colors.purple,
    dailyByCategory: Colors.pink,
    dailyByProduct: Colors.brown,
    top: Colors.amber,
    monthly: Colors.cyan,
  );

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    final years = [for (var y = currentYear; y >= currentYear - 5; y--) y];

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Graphiques'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: DropdownButton<int>(
                  value: _year,
                  dropdownColor: Theme.of(context).colorScheme.surface,
                  underline: const SizedBox.shrink(),
                  items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
                  onChanged: (value) {
                    if (value != null) setState(() => _year = value);
                  },
                ),
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [Tab(text: 'Recettes'), Tab(text: 'Bénéfices'), Tab(text: 'Stock'), Tab(text: 'Dépenses')],
          ),
        ),
        body: TabBarView(
          children: [
            MetricChartsTab(
              key: ValueKey('recettes-$_year'),
              establishmentId: widget.establishmentId,
              year: _year,
              metric: 'revenue',
              titles: _recettesTitles,
              palette: _recettesPalette,
            ),
            MetricChartsTab(
              key: ValueKey('benefices-$_year'),
              establishmentId: widget.establishmentId,
              year: _year,
              metric: 'profit',
              titles: _beneficesTitles,
              palette: _beneficesPalette,
            ),
            // Pas de clé liée à `_year` : voir la doc de classe, cet onglet
            // représente l'état courant du stock, pas une période.
            StockLotsTab(establishmentId: widget.establishmentId),
            ExpenseChartsTab(
              key: ValueKey('depenses-$_year'),
              establishmentId: widget.establishmentId,
              year: _year,
            ),
          ],
        ),
      ),
    );
  }
}
