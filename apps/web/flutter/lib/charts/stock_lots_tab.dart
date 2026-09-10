import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import 'chart_models.dart';
import 'charts_repository.dart';

/// Palette dédiée à ce sous-module : dominante vert (traçabilité / stock),
/// délibérément distincte des palettes bleu/violet de Recettes et Bénéfices —
/// reprend la demande du fichier de référence ("dominante vert foncé / vert,
/// avec des touches de bleu, orange et rouge pour les statuts").
class _StockPalette {
  static const darkGreen = Color(0xFF1B5E20);
  static const green = Color(0xFF2E7D32);
  static const paleGreen = Color(0xFFE8F5E9);
  static const borderGreen = Color(0xFFC8E6C9);
  static const grey = Color(0xFF9E9E9E);
  static const red = Color(0xFFC62828);
  static const paleRed = Color(0xFFFFEBEE);
  static const background = Color(0xFFF4FBF5);
}

/// Sous-module "Stock" du module Graphiques : fiche de lots FIFO d'un ou
/// plusieurs produits de même catégorie (maquette demandée — voir PROMPT et
/// docs/api/charts.md pour la logique de reconstruction des lots à partir de
/// l'historique des `StockMovement`, sans schéma de lot dédié, et pour le
/// principe de numérotation lot ↔ commande/marché).
///
/// Contrairement à `MetricChartsTab` (Recettes / Bénéfices), cet onglet
/// n'est PAS piloté par le filtre Année de `GraphiquesPage` : les lots FIFO
/// représentent l'état COURANT du stock, pas une période — un lot reçu il y
/// a plusieurs années peut rester actif aujourd'hui.
class StockLotsTab extends StatefulWidget {
  const StockLotsTab({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<StockLotsTab> createState() => _StockLotsTabState();
}

class _StockLotsTabState extends State<StockLotsTab> {
  late final ChartsRepository _charts = ChartsRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final CatalogRepository _catalog = CatalogRepository(
    ApiClient(),
    widget.establishmentId,
  );
  static final DateFormat _dayFormat = DateFormat('dd/MM/yyyy');

  List<Product> _products = [];
  List<Category> _categories = [];
  String? _categoryId;
  Set<String> _productIds = {};
  bool _historyTabSelected = false;
  Future<StockLotsChart>? _lotsFuture;
  Future<List<OutOfStockProduct>>? _outOfStockFuture;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadOutOfStock();
  }

  List<Product> get _productsInCategory =>
      _products.where((p) => p.categoryId == _categoryId).toList();

  Future<void> _loadProducts() async {
    try {
      final products = await _catalog.listProducts();
      final categories = await _catalog.listCategories();
      if (!mounted) return;
      final firstWithCategory = products
          .where((p) => p.categoryId != null)
          .toList();
      setState(() {
        _products = products;
        _categories = categories;
        _categoryId = firstWithCategory.isNotEmpty
            ? firstWithCategory.first.categoryId
            : null;
        _productIds = firstWithCategory.isNotEmpty
            ? {firstWithCategory.first.id}
            : {};
      });
      if (_productIds.isNotEmpty) _reload();
    } catch (_) {
      // Le FutureBuilder du tableau affiche déjà son propre état d'erreur
      // réseau ; ici il n'y a simplement pas de produit à proposer.
    }
  }

  void _loadOutOfStock() {
    final future = _charts.getOutOfStockProducts();
    future.ignore();
    // Corps bloc (pas `=>`) : une closure fléchée affectant un champ `Future`
    // renvoie la valeur de l'affectation, donc le `Future` lui-même — setState
    // le prendrait alors pour une closure `async` et lève une assertion.
    setState(() {
      _outOfStockFuture = future;
    });
  }

  void _reload() {
    // `..ignore()` avant `setState` : même garde que MetricChartsTab contre
    // un rejet "unhandled" en test (flutter_test répond quasi instantanément).
    final future = _charts.getStockLots(productIds: _productIds.toList());
    future.ignore();
    setState(() {
      _lotsFuture = future;
    });
  }

  void _onCategoryChanged(String? categoryId) {
    final firstOfCategory = _products
        .where((p) => p.categoryId == categoryId)
        .toList();
    setState(() {
      _categoryId = categoryId;
      _productIds = firstOfCategory.isNotEmpty
          ? {firstOfCategory.first.id}
          : {};
      _historyTabSelected = false;
    });
    if (_productIds.isNotEmpty) _reload();
  }

  Future<void> _openProductPicker() async {
    final candidates = _productsInCategory;
    if (candidates.isEmpty) return;
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (context) => _ProductMultiSelectDialog(
        products: candidates,
        initiallySelected: _productIds,
      ),
    );
    if (selected == null || selected.isEmpty) return;
    setState(() {
      _productIds = selected;
      _historyTabSelected = false;
    });
    _reload();
  }

  String _formatQuantity(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';

  Widget _statusBadge(StockLot lot) {
    final color = lot.isActive ? _StockPalette.green : _StockPalette.grey;
    final label = lot.isActive ? 'Actif' : 'Épuisé';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _tabButton(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        margin: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? _StockPalette.darkGreen : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? _StockPalette.darkGreen : Colors.black54,
          ),
        ),
      ),
    );
  }

  Widget _lotsTable(List<StockLot> lots) {
    if (lots.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('Aucun lot à afficher pour cette sélection')),
      );
    }
    final showProductColumn = _productIds.length > 1;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(_StockPalette.paleGreen),
        columns: [
          const DataColumn(label: Text('Lot')),
          if (showProductColumn) const DataColumn(label: Text('Produit')),
          const DataColumn(label: Text('Date réception')),
          const DataColumn(label: Text('Quantité reçue'), numeric: true),
          const DataColumn(label: Text('Consommé'), numeric: true),
          const DataColumn(label: Text('Perdu'), numeric: true),
          const DataColumn(label: Text('Restant'), numeric: true),
          const DataColumn(label: Text('Statut')),
        ],
        rows: [
          for (final lot in lots)
            DataRow(
              cells: [
                DataCell(
                  Text(
                    lot.code,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (showProductColumn) DataCell(Text(lot.productName)),
                DataCell(Text(_dayFormat.format(lot.receivedAt))),
                DataCell(Text(_formatQuantity(lot.receivedQuantity))),
                DataCell(Text(_formatQuantity(lot.consumedQuantity))),
                DataCell(Text(_formatQuantity(lot.lossQuantity))),
                DataCell(Text(_formatQuantity(lot.remainingQuantity))),
                DataCell(_statusBadge(lot)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _totalCard(StockLotsChart chart) {
    final label = chart.productNames.length > 1
        ? '${chart.productNames.length} PRODUITS SÉLECTIONNÉS'
        : chart.productNames.first.toUpperCase();
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _StockPalette.paleGreen,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _StockPalette.borderGreen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOTAL $label (LOTS ACTIFS)',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: _StockPalette.darkGreen,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_formatQuantity(chart.totalActiveUnits)} unités',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _StockPalette.darkGreen,
            ),
          ),
        ],
      ),
    );
  }

  String get _productPickerLabel {
    if (_productIds.isEmpty) return 'Sélectionner un produit';
    if (_productIds.length == 1) {
      final matches = _products.where((p) => p.id == _productIds.first);
      return matches.isEmpty ? 'Produit sélectionné' : matches.first.name;
    }
    return '${_productIds.length} produits sélectionnés';
  }

  Widget _outOfStockTable(List<OutOfStockProduct> products) {
    if (products.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('Aucun produit en rupture de stock')),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(_StockPalette.paleRed),
        columns: const [
          DataColumn(label: Text('Produit')),
          DataColumn(label: Text('Catégorie')),
          DataColumn(label: Text('Quantité en stock'), numeric: true),
        ],
        rows: [
          for (final product in products)
            DataRow(
              cells: [
                DataCell(
                  Text(
                    product.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataCell(Text(product.categoryName)),
                DataCell(
                  Text(
                    _formatQuantity(product.stockQuantity),
                    style: const TextStyle(
                      color: _StockPalette.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _StockPalette.background,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: _StockPalette.borderGreen),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('📦 ', style: TextStyle(fontSize: 20)),
                      Expanded(
                        child: Text(
                          'Détail d\'un produit',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: _StockPalette.darkGreen,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                      TextButton(
                        onPressed: _products.isEmpty
                            ? null
                            : () => setState(() => _historyTabSelected = true),
                        child: const Text('Voir tous les lots →'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_products.isEmpty)
                    const Text('Aucun produit au catalogue')
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _productsInCategory.isEmpty
                                ? null
                                : _openProductPicker,
                            icon: const Icon(Icons.arrow_drop_down),
                            label: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(_productPickerLabel),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _StockPalette.darkGreen,
                              side: const BorderSide(
                                color: _StockPalette.borderGreen,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            initialValue: _categoryId,
                            decoration: const InputDecoration(
                              labelText: 'Catégorie',
                              isDense: true,
                            ),
                            items: [
                              for (final category in _categories)
                                DropdownMenuItem(
                                  value: category.id,
                                  child: Text(category.name),
                                ),
                            ],
                            onChanged: _onCategoryChanged,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  if (_productIds.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'Ajoutez un produit au catalogue pour suivre son stock par lots',
                        ),
                      ),
                    )
                  else
                    FutureBuilder<StockLotsChart>(
                      future: _lotsFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (snapshot.hasError) {
                          final message = snapshot.error is ApiException
                              ? (snapshot.error as ApiException).message
                              : '${snapshot.error}';
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: Text(message)),
                          );
                        }
                        final chart = snapshot.data!;
                        final activeCount = chart.activeLots.length;
                        final historyCount = chart.historyLots.length;
                        final visibleLots = _historyTabSelected
                            ? chart.historyLots
                            : chart.activeLots;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _tabButton(
                                  'Lots actifs ($activeCount)',
                                  !_historyTabSelected,
                                  () => setState(
                                    () => _historyTabSelected = false,
                                  ),
                                ),
                                _tabButton(
                                  'Historique ($historyCount)',
                                  _historyTabSelected,
                                  () => setState(
                                    () => _historyTabSelected = true,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 1),
                            const SizedBox(height: 12),
                            _lotsTable(visibleLots),
                            _totalCard(chart),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.only(top: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: _StockPalette.borderGreen),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('⚠️ ', style: TextStyle(fontSize: 20)),
                      Expanded(
                        child: Text(
                          'Top des produits épuisés',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: _StockPalette.darkGreen,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<List<OutOfStockProduct>>(
                    future: _outOfStockFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError) {
                        final message = snapshot.error is ApiException
                            ? (snapshot.error as ApiException).message
                            : '${snapshot.error}';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: Text(message)),
                        );
                      }
                      return _outOfStockTable(snapshot.data!);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sélection multiple des produits d'une même catégorie (déclenchée par le
/// bouton "champ filtre Produit", qui reste visuellement une liste
/// déroulante) — présentée en boîte de dialogue à cases à cocher plutôt
/// qu'un `PopupMenuButton` pour éviter le conflit de geste bien connu entre
/// `PopupMenuItem` et une case à cocher imbriquée.
class _ProductMultiSelectDialog extends StatefulWidget {
  const _ProductMultiSelectDialog({
    required this.products,
    required this.initiallySelected,
  });

  final List<Product> products;
  final Set<String> initiallySelected;

  @override
  State<_ProductMultiSelectDialog> createState() =>
      _ProductMultiSelectDialogState();
}

class _ProductMultiSelectDialogState extends State<_ProductMultiSelectDialog> {
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initiallySelected);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sélectionner des produits'),
      content: SizedBox(
        width: 360,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final product in widget.products)
              CheckboxListTile(
                value: _selected.contains(product.id),
                title: Text(product.name),
                onChanged: (checked) {
                  setState(() {
                    if (checked == true) {
                      _selected.add(product.id);
                    } else {
                      _selected.remove(product.id);
                    }
                  });
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selected),
          child: const Text('Appliquer'),
        ),
      ],
    );
  }
}
