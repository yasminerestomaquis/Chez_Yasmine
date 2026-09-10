import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../catalog/catalog_cache.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../common/formatting.dart';
import '../sync/sync_queue_service.dart';
import '../sync/sync_status_bar.dart';
import '../theme/app_theme.dart';
import 'product_stock_history_page.dart';
import 'stock_models.dart';
import 'stock_movement_dialog.dart';
import 'stock_repository.dart';

const _kFilterAll = 'all';
const _kFilterInStock = 'in_stock';
const _kFilterLow = 'low';
const _kFilterOut = 'out';

class StockPage extends StatefulWidget {
  const StockPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  late final CatalogRepository _catalog = CatalogRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final StockRepository _stock = StockRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final CatalogCache _cache = CatalogCache(widget.establishmentId);
  late final SyncQueueService _syncQueue = SyncQueueService(
    ApiClient(),
    widget.establishmentId,
  );
  late Future<(List<StockAlert>, List<Product>)> _future = _load();

  String _search = '';
  String _filter = _kFilterAll;

  Future<(List<StockAlert>, List<Product>)> _load() async {
    try {
      final alerts = await _stock.listAlerts();
      final products = await _catalog.listProducts();
      return (alerts, products);
    } catch (error) {
      final cached = await _cache.load();
      if (cached != null) return (<StockAlert>[], cached.$2); // offline: stock levels shown may be stale, no alerts computed locally.
      rethrow;
    }
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _openMovementDialog(Product product) async {
    final created = await showStockMovementDialog(
      context,
      repository: _stock,
      productId: product.id,
      productName: product.name,
      hasVariablePricing: product.hasVariablePricing,
    );
    if (created == true) _reload();
  }

  // Coût unitaire effectif pour l'estimation de la valeur du stock : reprend
  // le prix d'achat par bouteille, ou le dérive du prix par casier quand
  // seule cette information est saisie (catégories à prix par casier) —
  // purement un calcul d'affichage côté client, aucune donnée nouvelle.
  double _unitCost(Product product) {
    if (product.purchasePrice != null) return product.purchasePrice!;
    if (product.purchasePricePerCase != null &&
        product.bottlesPerCase != null &&
        product.bottlesPerCase! > 0) {
      return product.purchasePricePerCase! / product.bottlesPerCase!;
    }
    return 0;
  }

  // Statut dérivé des données déjà chargées, sans nouvelle règle métier :
  // rupture si la quantité est nulle, faible si une alerte existe pour ce
  // produit, normal sinon.
  String _statusOf(Product product, StockAlert? alert) {
    if (product.stockQuantity <= 0) return _kFilterOut;
    if (alert != null) return _kFilterLow;
    return _kFilterInStock;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stock')),
      body: Column(
        children: [
          SyncStatusBar(syncQueue: _syncQueue),
          Expanded(
            child: FutureBuilder<(List<StockAlert>, List<Product>)>(
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

                final (alerts, allProducts) = snapshot.data!;
                final alertsByProduct = {for (final a in alerts) a.id: a};
                final outCount = allProducts
                    .where((p) => p.stockQuantity <= 0)
                    .length;
                final lowCount = alerts
                    .where((a) => a.stockQuantity > 0)
                    .length;
                final totalValue = allProducts.fold<double>(
                  0,
                  (sum, p) => sum + p.stockQuantity * _unitCost(p),
                );

                final products = allProducts.where((p) {
                  final matchesSearch =
                      _search.isEmpty ||
                      p.name.toLowerCase().contains(_search.toLowerCase());
                  if (!matchesSearch) return false;
                  if (_filter == _kFilterAll) return true;
                  return _statusOf(p, alertsByProduct[p.id]) == _filter;
                }).toList();

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
                          value: totalValue,
                        ),
                      ),
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
                          repository: _catalog,
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

class _StockKpiRow extends StatelessWidget {
  const _StockKpiRow({
    required this.total,
    required this.low,
    required this.out,
    required this.value,
  });

  final int total;
  final int low;
  final int out;
  final double value;

  @override
  Widget build(BuildContext context) {
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        mainAxisExtent: 84,
      ),
      children: [
        _kpiCard(
          Icons.inventory_2_outlined,
          'Articles suivis',
          '$total',
          AppColors.green,
        ),
        _kpiCard(
          Icons.warning_amber_outlined,
          'Stock faible',
          '$low',
          AppColors.orange,
        ),
        _kpiCard(
          Icons.remove_shopping_cart_outlined,
          'Ruptures',
          '$out',
          AppColors.alert,
        ),
        _kpiCard(
          Icons.payments_outlined,
          'Valeur du stock',
          '${formatAmount(value)} F',
          AppColors.green,
        ),
      ],
    );
  }

  Widget _kpiCard(IconData icon, String label, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockProductRow extends StatelessWidget {
  const _StockProductRow({
    required this.product,
    required this.alert,
    required this.repository,
    required this.onHistory,
    required this.onMovement,
  });

  final Product product;
  final StockAlert? alert;
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
                    'Stock actuel : ${product.stockQuantity.toStringAsFixed(0)}${minStock > 0 ? ' (seuil ${minStock.toStringAsFixed(0)})' : ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Actions',
              onSelected: (value) {
                if (value == 'history') onHistory();
                if (value == 'movement') onMovement();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'movement',
                  child: Text('Mouvement de stock'),
                ),
                PopupMenuItem(
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
