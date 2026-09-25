import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../common/browser_download.dart';
import '../common/formatting.dart';
import '../common/gridded_table.dart';
import 'chart_models_permissions.dart';
import 'charts_repository.dart';
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

class _GraphiquesPageState extends State<GraphiquesPage>
    with SingleTickerProviderStateMixin {
  late int _year = DateTime.now().year;

  late final ChartsRepository _charts = ChartsRepository(
    ApiClient(),
    widget.establishmentId,
  );

  /// Graphiques autorisés au rôle courant (`charts.*`, voir « Gestion des
  /// permissions »). En cas d'échec du chargement (hors ligne, erreur), tous
  /// sont proposés : le serveur refuse de toute façon ceux qui ne sont pas
  /// accordés, chaque graphique affichant alors son propre message d'erreur.
  late final Future<Set<String>> _permissions =
      _charts.getMyPermissions().catchError((_) => allChartPermissions);

  /// Index de l'onglet Bénéfices dans `_tabController`/`TabBarView` — le
  /// bouton "Repas" de l'AppBar (demande utilisateur du 2026-09-25) n'est
  /// affiché que sur cet onglet, contrairement au filtre Année qui reste
  /// visible sur les quatre.
  static const _beneficesTabIndex = 1;

  late final TabController _tabController = TabController(length: 4, vsync: this)
    ..addListener(() {
      // `indexIsChanging` reste vrai pendant l'animation de balayage — ne
      // reconstruire qu'une fois l'onglet effectivement établi, pour ne pas
      // faire clignoter le bouton "Repas" pendant la transition.
      if (!_tabController.indexIsChanging) setState(() {});
    });

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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

  // Libellés distinguant explicitement "bénéfice net" (Total/Mensuel :
  // déduit toutes les dépenses et pertes) de "marge brute" (Par
  // catégorie/Par produit/Top : recette moins coût d'achat uniquement) —
  // avant, les 5 portaient le même mot "Bénéfices", ce qui rendait
  // incompréhensible qu'un Total puisse être négatif alors que sa
  // ventilation par catégorie est positive sur la même semaine (décision
  // utilisateur du 2026-09-25, voir aussi `groupNetVsGross` sur
  // `MetricChartsTab`).
  static const _beneficesTitles = ChartTitles(
    dailyTotal: 'Bénéfice net — journalier',
    dailyByCategory: 'Marge brute — journalière par catégorie',
    dailyByProduct: 'Marge brute — journalière par produit',
    top: 'Top marge brute (par produit)',
    monthly: 'Bénéfice net — mensuel',
  );

  static const _beneficesPalette = ChartPalette(
    dailyTotal: Colors.purple,
    dailyByCategory: Colors.pink,
    dailyByProduct: Colors.brown,
    top: Colors.amber,
    monthly: Colors.cyan,
  );

  /// Listing "Repas" (bouton de l'AppBar, onglet Bénéfices uniquement —
  /// demande utilisateur du 2026-09-25) : cumule Plats africains/Poissons/
  /// Poulets en une seule ligne "Repas" (`ChartsService.mealsProfitListing`,
  /// tout l'historique, pas de filtre de période). Tableau à quadrillage
  /// complet et défilable (`griddedTable`), exactement deux lignes de
  /// données ("Repas" puis "TOTAL", identiques — une seule ligne agrégée),
  /// même principe que les autres listings de l'application.
  Future<void> _showMealsProfitListing() async {
    try {
      final listing = await _charts.getMealsProfitListing();
      final rateText = '${listing.rate.toStringAsFixed(2)} %';
      final row = [
        'Repas',
        formatAmount(listing.marketCost),
        formatAmount(listing.currentRevenue),
        formatAmount(listing.profit),
        rateText,
      ];

      if (!mounted) return;
      final exportRequested = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Repas'),
          content: SizedBox(
            width: double.maxFinite,
            child: griddedTable(
              context,
              headers: const [
                'Repas',
                'Prix marché (FCFA)',
                'Recette actuelle (FCFA)',
                'Bénéfice (FCFA)',
                'Taux',
              ],
              numericColumns: const [false, true, true, true, true],
              rows: [row],
              totalRow: ['TOTAL', row[1], row[2], row[3], row[4]],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Fermer'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Exporter en PDF'),
            ),
          ],
        ),
      );
      if (exportRequested == true) {
        await _downloadMealsProfitListingPdf();
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _downloadMealsProfitListingPdf() async {
    try {
      final result = await _charts.exportMealsProfitListingPdf();
      downloadBytes(result.bytes, result.filename ?? 'Repas.pdf');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    final years = [for (var y = currentYear; y >= currentYear - 5; y--) y];

    return FutureBuilder<Set<String>>(
      future: _permissions,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: const Text('Graphiques')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        return _buildTabs(context, snapshot.data ?? allChartPermissions, years);
      },
    );
  }

  Widget _buildTabs(
    BuildContext context,
    Set<String> allowed,
    List<int> years,
  ) {
    final onBenefices = _tabController.index == _beneficesTabIndex;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Graphiques'),
        actions: [
          if (onBenefices && allowed.contains('charts.profit_meals_listing'))
            IconButton(
              tooltip: 'Repas (listing, export PDF)',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: _showMealsProfitListing,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: DropdownButton<int>(
                value: _year,
                dropdownColor: Theme.of(context).colorScheme.surface,
                underline: const SizedBox.shrink(),
                items: [
                  for (final y in years)
                    DropdownMenuItem(value: y, child: Text('$y')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _year = value);
                },
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Recettes'),
            Tab(text: 'Bénéfices'),
            Tab(text: 'Stock'),
            Tab(text: 'Dépenses'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          MetricChartsTab(
            key: ValueKey('recettes-$_year'),
            establishmentId: widget.establishmentId,
            year: _year,
            metric: 'revenue',
            permissionKey: 'revenue',
            allowed: allowed,
            titles: _recettesTitles,
            palette: _recettesPalette,
            showWeeklyRevenueTrend: true,
          ),
          MetricChartsTab(
            key: ValueKey('benefices-$_year'),
            establishmentId: widget.establishmentId,
            year: _year,
            metric: 'profit',
            permissionKey: 'profit',
            allowed: allowed,
            titles: _beneficesTitles,
            palette: _beneficesPalette,
            groupNetVsGross: true,
          ),
          // Pas de clé liée à `_year` : voir la doc de classe, cet onglet
          // représente l'état courant du stock, pas une période.
          StockLotsTab(
            establishmentId: widget.establishmentId,
            allowed: allowed,
          ),
          ExpenseChartsTab(
            key: ValueKey('depenses-$_year'),
            establishmentId: widget.establishmentId,
            year: _year,
            allowed: allowed,
          ),
        ],
      ),
    );
  }
}
