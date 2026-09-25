import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../catalog/catalog_cache.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../charts/charts_repository.dart';
import '../common/browser_download.dart';
import '../common/formatting.dart';
import '../common/gridded_table.dart';
import '../theme/app_theme.dart';
import 'product_stock_history_page.dart';
import 'stock_models.dart';
import 'stock_movement_dialog.dart';
import 'stock_repository.dart';
import 'stock_value.dart';

const _kFilterAll = 'all';
const _kFilterInStock = 'in_stock';
const _kFilterLow = 'low';
const _kFilterOut = 'out';

// Statut dérivé des données déjà chargées, sans nouvelle règle métier :
// rupture si la quantité est nulle, faible si une alerte existe pour ce
// produit, normal sinon.
String stockStatusOf(Product product, StockAlert? alert) {
  if (product.stockQuantity <= 0) return _kFilterOut;
  if (alert != null) return _kFilterLow;
  return _kFilterInStock;
}

/// Filtre (recherche, catégories sélectionnées, statut) puis trie par ordre
/// croissant de stock actuel (demande utilisateur du 2026-09-16) — logique
/// pure, testable sans widget ni réseau (voir `test/stock_page_test.dart`).
List<Product> filterAndSortStockProducts({
  required List<Product> products,
  required Map<String, StockAlert> alertsByProduct,
  required String search,
  required String statusFilter,
  required Set<String> selectedCategoryIds,
}) {
  return products.where((p) {
    final matchesSearch =
        search.isEmpty || p.name.toLowerCase().contains(search.toLowerCase());
    if (!matchesSearch) return false;
    if (selectedCategoryIds.isNotEmpty &&
        !selectedCategoryIds.contains(p.categoryId)) {
      return false;
    }
    if (statusFilter == _kFilterAll) return true;
    return stockStatusOf(p, alertsByProduct[p.id]) == statusFilter;
  }).toList()..sort((a, b) => a.stockQuantity.compareTo(b.stockQuantity));
}

class _StockPageData {
  const _StockPageData({
    required this.alerts,
    required this.products,
    required this.categories,
    required this.totals,
    required this.canViewValue,
  });

  final List<StockAlert> alerts;
  final List<Product> products;
  final List<Category> categories;
  final List<StockMovementTotals> totals;

  /// Permission `stock.view_value` — visibilité du groupe « Valeur du stock »
  /// (demande utilisateur du 2026-09-22, "Gestion des permissions" > Stock).
  /// Par défaut réservée au Super Administrateur.
  final bool canViewValue;
}

class StockPage extends StatefulWidget {
  const StockPage({
    super.key,
    required this.establishmentId,
    required this.roleName,
  });

  final String establishmentId;
  final String roleName;

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  // Comparaison par nom de rôle — même limitation/raison que
  // HomeDashboard._isServeur (voir lib/home/home_dashboard.dart) : `GET
  // /auth/me` n'expose pas de code de permission au client. Demande
  // utilisateur du 2026-09-11 : le Serveur a `stock.view` (lecture) mais pas
  // `stock.manage` — accès en lecture seule (pas de "Mouvement de stock").
  bool get _isServeur => widget.roleName == 'Serveur';

  late final CatalogRepository _catalog = CatalogRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final StockRepository _stock = StockRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final ChartsRepository _charts = ChartsRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final CatalogCache _cache = CatalogCache(widget.establishmentId);
  late Future<_StockPageData> _future = _load();

  String _search = '';
  String _filter = _kFilterAll;
  // Vide = toutes les catégories (pas de filtre) — sélection multiple,
  // demande utilisateur du 2026-09-16.
  Set<String> _selectedCategoryIds = {};
  // Filtre propre au groupe « Valeur du stock » (indépendant du filtre de la liste).
  Set<String> _valueCategoryIds = {};

  Future<_StockPageData> _load() async {
    try {
      final (alerts, products, categories, totals, permissions) = await (
        _stock.listAlerts(),
        _catalog.listProducts(),
        _catalog.listCategories(),
        _stock.listMovementTotals(),
        // Échec (réseau, ou rôle qui n'a même pas stock.view) : groupe masqué
        // par défaut, un chiffre potentiellement sensible reste donc jamais
        // affiché faute de mieux.
        _stock.getMyPermissions().catchError((_) => <String>{}),
      ).wait;
      return _StockPageData(
        alerts: alerts,
        products: products,
        categories: categories,
        totals: totals,
        canViewValue: permissions.contains('stock.view_value'),
      );
    } catch (error) {
      final cached = await _cache.load();
      if (cached != null) {
        // Offline : niveaux de stock potentiellement obsolètes, ni alertes
        // ni totaux de mouvements calculables localement.
        return _StockPageData(
          alerts: const [],
          products: cached.$2,
          categories: cached.$1,
          totals: const [],
          canViewValue: false,
        );
      }
      rethrow;
    }
  }

  void _reload() => setState(() => _future = _load());

  static String _qty(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2);

  /// Listing "Stock actif" (bouton de l'AppBar — demande utilisateur du
  /// 2026-09-25) : un produit = une ligne, agrégée sur ses seuls lots FIFO
  /// actifs (`ChartsService.activeStockListing`, même critère que « Lots
  /// actifs » dans Graphiques > Stock > Détail d'un produit). Tableau à
  /// quadrillage complet et défilable (`griddedTable`), même principe que les
  /// listings « Boissons vendues »/« Plats vendus » du module Rapports.
  Future<void> _showActiveStockListing() async {
    try {
      final rows = await _charts.getActiveStockListing();
      final totals = rows.fold<({double received, double consumed, double consumedRevenue, double loss, double lossRevenue, double remaining, double remainingRevenue})>(
        (
          received: 0,
          consumed: 0,
          consumedRevenue: 0,
          loss: 0,
          lossRevenue: 0,
          remaining: 0,
          remainingRevenue: 0,
        ),
        (acc, r) => (
          received: acc.received + r.receivedQuantity,
          consumed: acc.consumed + r.consumedQuantity,
          consumedRevenue: acc.consumedRevenue + r.consumedRevenue,
          loss: acc.loss + r.lossQuantity,
          lossRevenue: acc.lossRevenue + r.lossRevenue,
          remaining: acc.remaining + r.remainingQuantity,
          remainingRevenue: acc.remainingRevenue + r.remainingRevenue,
        ),
      );

      if (!mounted) return;
      final exportRequested = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Stock actif'),
          content: SizedBox(
            width: double.maxFinite,
            child: rows.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Aucun produit avec du stock actif.'),
                  )
                : griddedTable(
                    context,
                    headers: const [
                      'Produit',
                      'Qté reçue',
                      'Consommé',
                      'Recette consommé (FCFA)',
                      'Perdu',
                      'Recette perdue (FCFA)',
                      'Restant',
                      'Recette stock (FCFA)',
                    ],
                    numericColumns: const [false, true, true, true, true, true, true, true],
                    rows: [
                      for (final r in rows)
                        [
                          r.productName,
                          _qty(r.receivedQuantity),
                          _qty(r.consumedQuantity),
                          formatAmount(r.consumedRevenue),
                          _qty(r.lossQuantity),
                          formatAmount(r.lossRevenue),
                          _qty(r.remainingQuantity),
                          formatAmount(r.remainingRevenue),
                        ],
                    ],
                    totalRow: [
                      'TOTAL',
                      _qty(totals.received),
                      _qty(totals.consumed),
                      formatAmount(totals.consumedRevenue),
                      _qty(totals.loss),
                      formatAmount(totals.lossRevenue),
                      _qty(totals.remaining),
                      formatAmount(totals.remainingRevenue),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Fermer'),
            ),
            if (rows.isNotEmpty)
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Exporter en PDF'),
              ),
          ],
        ),
      );
      if (exportRequested == true) {
        await _downloadActiveStockListingPdf();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _downloadActiveStockListingPdf() async {
    try {
      final result = await _charts.exportActiveStockListingPdf();
      downloadBytes(result.bytes, result.filename ?? 'Stock actif.pdf');
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openMovementDialog(Product product) async {
    final created = await showStockMovementDialog(
      context,
      repository: _stock,
      productId: product.id,
      productName: product.name,
      hasVariablePricing: product.hasVariablePricing,
      isReferencePriced: product.isReferencePriced,
    );
    if (created == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock'),
        actions: [
          IconButton(
            tooltip: 'Stock actif (listing, export PDF)',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _showActiveStockListing,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<_StockPageData>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  final message = snapshot.error is ApiException
                      ? (snapshot.error as ApiException).message
                      : '${snapshot.error}';
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off, size: 40),
                          const SizedBox(height: 12),
                          Text(message, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _reload,
                            child: const Text('Réessayer'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final data = snapshot.data!;
                final alerts = data.alerts;
                final allProducts = data.products;
                final categories = data.categories;
                final totalsByProduct = {
                  for (final t in data.totals) t.productId: t,
                };
                final alertsByProduct = {for (final a in alerts) a.id: a};
                final outCount = allProducts
                    .where((p) => p.stockQuantity <= 0)
                    .length;
                final lowCount = alerts
                    .where((a) => a.stockQuantity > 0)
                    .length;
                final valueTotals = stockValueTotals(
                  allProducts,
                  _valueCategoryIds,
                );
                // Rangée du haut (Articles suivis/Stock faible/Ruptures) :
                // total fixe, non filtré — indépendant du filtre Catégorie
                // du groupe « Valeur du stock ». Vignette du groupe : suit
                // ce filtre, comme Prix d'achat/Prix de vente (demande
                // utilisateur du 2026-09-22).
                final totalBottleCount = stockBottleCount(allProducts, {});
                final valueBottleCount = stockBottleCount(allProducts, _valueCategoryIds);
                // Filtre Catégorie du groupe portant sur Gbêlê (ou un autre
                // produit à prix de référence variable) : « Bouteilles en
                // stock » n'a pas de sens, remplacée par « Stock en litres »
                // — demande utilisateur du 2026-09-25.
                final valueShowsLiters = hasReferencePricedSelection(allProducts, _valueCategoryIds);
                final valueLiters = stockReferenceLiters(allProducts, _valueCategoryIds);

                final products = filterAndSortStockProducts(
                  products: allProducts,
                  alertsByProduct: alertsByProduct,
                  search: _search,
                  statusFilter: _filter,
                  selectedCategoryIds: _selectedCategoryIds,
                );

                return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: _StockKpiRow(
                          total: allProducts.length,
                          low: lowCount,
                          out: outCount,
                          bottles: totalBottleCount,
                        ),
                      ),
                      if (data.canViewValue) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: _StockValueBox(
                            categories: categories,
                            selectedIds: _valueCategoryIds,
                            onChanged: (ids) =>
                                setState(() => _valueCategoryIds = ids),
                            purchase: valueTotals.purchase,
                            sale: valueTotals.sale,
                            bottleCount: valueBottleCount,
                            showLiters: valueShowsLiters,
                            literCount: valueLiters,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: TextField(
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            labelText: 'Rechercher un article',
                            isDense: true,
                          ),
                          onChanged: (value) => setState(() => _search = value),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          children: [
                            _filterChip('Tous', _kFilterAll),
                            _filterChip('En stock', _kFilterInStock),
                            _filterChip('Stock faible', _kFilterLow),
                            _filterChip('Rupture', _kFilterOut),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: _CategoryFilterField(
                          categories: categories,
                          selectedIds: _selectedCategoryIds,
                          onChanged: (ids) =>
                              setState(() => _selectedCategoryIds = ids),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (products.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text('Aucun article dans ce filtre.'),
                          ),
                        ),
                      for (final product in products)
                        _StockProductRow(
                          product: product,
                          alert: alertsByProduct[product.id],
                          totals: totalsByProduct[product.id],
                          repository: _catalog,
                          readOnly: _isServeur,
                          onHistory: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ProductStockHistoryPage(
                                repository: _stock,
                                productId: product.id,
                                productName: product.name,
                              ),
                            ),
                          ),
                          onMovement: () => _openMovementDialog(product),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _filter = value),
        selectedColor: AppColors.green,
        labelStyle: TextStyle(
          color: selected ? AppColors.white : AppColors.textPrimary,
        ),
      ),
    );
  }
}

/// Filtre par catégorie sous forme de liste déroulante, avec sélection
/// multiple et réinitialisation (demande utilisateur du 2026-09-16) — pas de
/// widget Flutter natif pour un menu déroulant à cases à cocher, donc un
/// simple champ cliquable ouvrant un dialogue `CheckboxListTile` par
/// catégorie, même principe que `CatalogPage._showCategoryDialog`.
class _CategoryFilterField extends StatelessWidget {
  const _CategoryFilterField({
    required this.categories,
    required this.selectedIds,
    required this.onChanged,
  });

  final List<Category> categories;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onChanged;

  String get _label {
    if (selectedIds.isEmpty) return 'Toutes les catégories';
    if (selectedIds.length == 1) {
      return categories
          .firstWhere(
            (c) => c.id == selectedIds.first,
            orElse: () => Category(id: '', name: '1 catégorie'),
          )
          .name;
    }
    return '${selectedIds.length} catégories sélectionnées';
  }

  Future<void> _open(BuildContext context) async {
    var working = Set<String>.from(selectedIds);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Filtrer par catégorie'),
          content: SizedBox(
            width: 360,
            child: categories.isEmpty
                ? const Text('Aucune catégorie.')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final category in categories)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: working.contains(category.id),
                          title: Text(category.name),
                          onChanged: (checked) => setDialogState(() {
                            if (checked ?? false) {
                              working.add(category.id);
                            } else {
                              working.remove(category.id);
                            }
                          }),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => setDialogState(() => working = {}),
              child: const Text('Réinitialiser'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(selectedIds),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(working),
              child: const Text('Appliquer'),
            ),
          ],
        ),
      ),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => _open(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Catégorie',
          prefixIcon: const Icon(Icons.filter_list),
          suffixIcon: selectedIds.isEmpty
              ? const Icon(Icons.arrow_drop_down)
              : IconButton(
                  tooltip: 'Réinitialiser le filtre',
                  icon: const Icon(Icons.clear),
                  onPressed: () => onChanged({}),
                ),
        ),
        child: Text(_label, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _StockKpiRow extends StatelessWidget {
  const _StockKpiRow({
    required this.total,
    required this.low,
    required this.out,
    required this.bottles,
  });

  final int total;
  final int low;
  final int out;

  /// « Bouteilles en stock » (catégories à prix par casier — Bières, Vins,
  /// Sucreries), fixe et non filtré, distinct de la vignette homonyme du
  /// groupe « Valeur du stock » qui suit son propre filtre Catégorie —
  /// demande utilisateur du 2026-09-22.
  final double bottles;

  @override
  Widget build(BuildContext context) {
    // Une seule ligne horizontale (demande utilisateur du 2026-09-22) ; la
    // « Valeur du stock » a quitté cette rangée pour son propre groupe.
    return Row(
      children: [
        Expanded(
          child: _kpiCard(
            Icons.inventory_2_outlined,
            'Articles suivis',
            '$total',
            AppColors.green,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _kpiCard(
            Icons.warning_amber_outlined,
            'Stock faible',
            '$low',
            AppColors.orange,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _kpiCard(
            Icons.remove_shopping_cart_outlined,
            'Ruptures',
            '$out',
            AppColors.alert,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _kpiCard(
            Icons.sports_bar_outlined,
            'Bouteilles en stock',
            bottles.toStringAsFixed(0),
            AppColors.green,
          ),
        ),
      ],
    );
  }

  Widget _kpiCard(IconData icon, String label, String value, Color color) =>
      _kpiTile(icon, label, value, color);
}

/// Vignette KPI compacte (icône, valeur, libellé) — partagée par la rangée
/// des compteurs et le groupe « Valeur du stock ».
Widget _kpiTile(IconData icon, String label, String value, Color color) {
  return Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

/// Groupe « Valeur du stock » : filtre Catégorie (sélection multiple,
/// réinitialisable) et trois vignettes sur une seule ligne — Prix d'achat,
/// Prix de vente et Bouteilles en stock (restreint aux catégories vendues
/// par casier — Bières, Vins, Sucreries), toutes les trois calculées sur
/// les catégories choisies dans le filtre (tout le catalogue sans
/// sélection) — demande utilisateur du 2026-09-22. La troisième vignette
/// devient « Stock en litres » quand la sélection porte sur un produit à
/// prix de référence variable (ex. Gbêlê) — demande utilisateur du
/// 2026-09-25, voir `hasReferencePricedSelection`/`stockReferenceLiters`.
class _StockValueBox extends StatelessWidget {
  const _StockValueBox({
    required this.categories,
    required this.selectedIds,
    required this.onChanged,
    required this.purchase,
    required this.sale,
    required this.bottleCount,
    required this.showLiters,
    required this.literCount,
  });

  final List<Category> categories;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onChanged;
  final double purchase;
  final double sale;
  final double bottleCount;
  final bool showLiters;
  final double literCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.green.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Valeur du stock',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 10),
          _CategoryFilterField(
            categories: categories,
            selectedIds: selectedIds,
            onChanged: onChanged,
          ),
          const SizedBox(height: 10),
          // Les 3 vignettes sur une seule ligne horizontale (demande
          // utilisateur du 2026-09-22).
          Row(
            children: [
              Expanded(
                child: _kpiTile(
                  Icons.shopping_cart_outlined,
                  "Prix d'achat",
                  '${formatAmount(purchase)} F',
                  AppColors.orange,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _kpiTile(
                  Icons.payments_outlined,
                  'Prix de vente',
                  '${formatAmount(sale)} F',
                  AppColors.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: showLiters
                    ? _kpiTile(
                        Icons.local_drink_outlined,
                        'Stock en litres',
                        '${literCount.toStringAsFixed(2)} L',
                        AppColors.green,
                      )
                    : _kpiTile(
                        Icons.sports_bar_outlined,
                        'Bouteilles en stock',
                        bottleCount.toStringAsFixed(0),
                        AppColors.green,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StockProductRow extends StatelessWidget {
  const _StockProductRow({
    required this.product,
    required this.alert,
    required this.totals,
    required this.repository,
    required this.readOnly,
    required this.onHistory,
    required this.onMovement,
  });

  final Product product;
  final StockAlert? alert;
  // Nul : aucun mouvement enregistré pour ce produit — les trois totaux
  // s'affichent alors à 0 plutôt que de masquer la ligne de statistiques.
  final StockMovementTotals? totals;
  // Masque l'action "Mouvement de stock" (rôle Serveur : `stock.view` sans
  // `stock.manage`, demande utilisateur du 2026-09-11) — "Voir l'historique"
  // reste toujours disponible.
  final bool readOnly;
  final CatalogRepository repository;
  final VoidCallback onHistory;
  final VoidCallback onMovement;

  Color get _statusColor {
    if (product.stockQuantity <= 0) return AppColors.alert;
    if (alert != null) return AppColors.orange;
    return AppColors.green;
  }

  String get _statusLabel {
    if (product.stockQuantity <= 0) return 'Rupture';
    if (alert != null) return 'Stock faible';
    return 'Normal';
  }

  @override
  Widget build(BuildContext context) {
    final minStock = product.minStock ?? 0;
    final progress = minStock > 0
        ? (product.stockQuantity / (minStock * 2)).clamp(0.0, 1.0)
        : (product.stockQuantity > 0 ? 1.0 : 0.0);
    final primaryImage =
        product.images.where((i) => i.isPrimary).firstOrNull ??
        product.images.firstOrNull;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 48,
                height: 48,
                child: primaryImage == null
                    ? const ColoredBox(
                        color: AppColors.greenLight,
                        child: Icon(
                          Icons.local_drink_outlined,
                          color: AppColors.green,
                        ),
                      )
                    : FutureBuilder<String>(
                        future: repository.getImageUrl(
                          product.id,
                          primaryImage.id,
                          variant: 'thumbnail',
                        ),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const ColoredBox(
                              color: AppColors.greenLight,
                            );
                          }
                          return ColoredBox(
                            color: AppColors.greenLight,
                            child: Image.network(
                              snapshot.data!,
                              fit: BoxFit.contain,
                            ),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _statusLabel,
                          style: TextStyle(
                            color: _statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (product.category != null)
                    Text(
                      product.category!.name,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: AppColors.orangeLight,
                      valueColor: AlwaysStoppedAnimation(_statusColor),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product.isReferencePriced
                        // Gbêlê : stock en litres et prix de vente ATTENDU du
                        // stock actuel (quantité × prix de référence), pas un
                        // simple taux au litre — demande utilisateur du
                        // 2026-09-25. 2 décimales, comme le reste de l'app
                        // pour une quantité fractionnaire (ex.
                        // `LossPricingChoice`), plutôt que l'entier habituel
                        // de cette ligne.
                        ? 'Stock actuel : ${product.stockQuantity.toStringAsFixed(2)} L — '
                              'Prix de vente attendu : '
                              '${formatAmount(product.stockQuantity * product.referenceSalePrice!)} FCFA'
                        : 'Stock actuel : ${product.stockQuantity.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _statusColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _MovementTotalsRow(totals: totals),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Actions',
              onSelected: (value) {
                if (value == 'history') onHistory();
                if (value == 'movement') onMovement();
              },
              itemBuilder: (context) => [
                if (!readOnly)
                  const PopupMenuItem(
                    value: 'movement',
                    child: Text('Mouvement de stock'),
                  ),
                const PopupMenuItem(
                  value: 'history',
                  child: Text('Voir l\'historique'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Trois totaux cumulés côte à côte (reçue/consommée/perte), même structure
/// visuelle compacte pour chacun — icône + valeur en gras + libellé, séparés
/// par de fins traits verticaux (demande utilisateur du 2026-09-16 :
/// « organise de manière intelligente et structurée » ces chiffres dans la
/// vignette). `totals` nul (aucun mouvement pour ce produit) affiche 0
/// partout plutôt que de masquer la ligne.
class _MovementTotalsRow extends StatelessWidget {
  const _MovementTotalsRow({required this.totals});

  final StockMovementTotals? totals;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MovementStat(
            icon: Icons.call_received,
            color: AppColors.green,
            value: totals?.received ?? 0,
            label: 'Reçue',
          ),
        ),
        const _StatDivider(),
        Expanded(
          child: _MovementStat(
            icon: Icons.shopping_cart_outlined,
            color: AppColors.orange,
            value: totals?.consumed ?? 0,
            label: 'Consommée',
          ),
        ),
        const _StatDivider(),
        Expanded(
          child: _MovementStat(
            icon: Icons.report_problem_outlined,
            color: AppColors.alert,
            value: totals?.lost ?? 0,
            label: 'Perte',
          ),
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: AppColors.orangeLight,
    );
  }
}

class _MovementStat extends StatelessWidget {
  const _MovementStat({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final double value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
            Text(
              value.toStringAsFixed(0),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
