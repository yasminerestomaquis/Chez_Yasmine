import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../catalog/catalog_cache.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../sync/sync_queue_service.dart';
import '../sync/sync_status_bar.dart';
import '../theme/app_theme.dart';
import 'product_stock_history_page.dart';
import 'stock_models.dart';
import 'stock_movement_dialog.dart';
import 'stock_repository.dart';

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
    );
    if (created == true) _reload();
  }

  // Purement un indicateur visuel : rupture/stock faible/OK, dérivé des
  // données déjà chargées (quantité du produit + éventuelle alerte), sans
  // appel ni règle métier supplémentaire.
  Widget _stockStatusPill(Product product, StockAlert? alert) {
    final Color color;
    if (product.stockQuantity <= 0) {
      color = AppColors.alert;
    } else if (alert != null) {
      color = AppColors.orange;
    } else {
      color = AppColors.green;
    }
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
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

                final (alerts, products) = snapshot.data!;
                final alertsByProduct = {for (final a in alerts) a.id: a};
                return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      if (alerts.isNotEmpty)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                          decoration: BoxDecoration(
                            color: AppColors.orangeLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber_outlined,
                                    color: AppColors.orange,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Alertes stock bas',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              for (final alert in alerts)
                                Text(
                                  '${alert.name} : ${alert.stockQuantity.toStringAsFixed(0)} (seuil ${alert.minStock.toStringAsFixed(0)})',
                                ),
                            ],
                          ),
                        ),
                      for (final product in products)
                        ListTile(
                          title: Text(product.name),
                          subtitle: Text(
                            'Stock actuel : ${product.stockQuantity.toStringAsFixed(0)}',
                          ),
                          leading: _stockStatusPill(
                            product,
                            alertsByProduct[product.id],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Historique',
                                icon: const Icon(Icons.history),
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ProductStockHistoryPage(
                                      repository: _stock,
                                      productId: product.id,
                                      productName: product.name,
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Ajouter un mouvement',
                                icon: const Icon(Icons.add_box_outlined),
                                onPressed: () => _openMovementDialog(product),
                              ),
                            ],
                          ),
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
}
