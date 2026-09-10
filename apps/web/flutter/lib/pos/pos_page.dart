import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../catalog/catalog_cache.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../sync/device_id.dart';
import '../sync/pending_operation.dart';
import '../sync/sync_queue_service.dart';
import '../sync/sync_status_bar.dart';
import 'cart_panel.dart';
import 'payment_dialog.dart';
import 'pos_models.dart';
import 'pos_repository.dart';
import 'product_grid.dart';
import 'receipt_page.dart';

/// Largeur en dessous de laquelle le panier passe en panneau inférieur
/// (bottom sheet + barre flottante) plutôt qu'en colonne latérale fixe —
/// recommandation de "Nouvel interface _ 1.docx" : le panier ne doit jamais
/// se retrouver compressé sur un écran de smartphone.
const _kMobileBreakpoint = 700.0;

class PosPage extends StatefulWidget {
  const PosPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  late final CatalogRepository _catalog = CatalogRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final PosRepository _pos = PosRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final CatalogCache _cache = CatalogCache(widget.establishmentId);
  late final SyncQueueService _syncQueue = SyncQueueService(
    ApiClient(),
    widget.establishmentId,
  );
  late Future<(List<Category>, List<Product>)> _future = _load();

  final List<CartLine> _cart = [];
  String _search = '';
  String? _categoryId;
  bool _isCharging = false;

  Future<(List<Category>, List<Product>)> _load() async {
    try {
      final categories = await _catalog.listCategories();
      final products = await _catalog.listProducts();
      await _cache.save(categories, products);
      return (categories, products);
    } catch (error) {
      final cached = await _cache.load();
      if (cached != null) return cached; // offline: fall back to the last known catalog (prompt maître §25).
      rethrow;
    }
  }

  double get _subtotal => _cart.fold(0, (sum, line) => sum + line.lineTotal);
  int get _itemCount => _cart.fold(0, (sum, line) => sum + line.quantity);

  Future<void> _addToCart(Product product) async {
    // Catégorie à prix variable (ex. Poulets/Poissons/Plats africains) :
    // aucun prix par défaut à proposer — le caissier le saisit à chaque
    // ajout, une ligne distincte par prix saisi (deux pièces de poulet
    // peuvent valoir des prix différents le même jour).
    if (product.salePrice == null) {
      final price = await _promptManualPrice(product);
      if (price == null) return;
      setState(
        () => _cart.add(
          CartLine(product: product, quantity: 1, manualUnitPrice: price),
        ),
      );
      return;
    }
    setState(() {
      final existing = _cart
          .where((l) => l.product.id == product.id)
          .firstOrNull;
      if (existing != null) {
        existing.quantity++;
      } else {
        _cart.add(CartLine(product: product, quantity: 1));
      }
    });
  }

  Future<double?> _promptManualPrice(Product product) async {
    final controller = TextEditingController();
    return showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Prix de vente — ${product.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Prix (FCFA)'),
          onSubmitted: (_) {
            final value = double.tryParse(
              controller.text.trim().replaceAll(',', '.'),
            );
            if (value != null && value > 0) Navigator.of(context).pop(value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(
                controller.text.trim().replaceAll(',', '.'),
              );
              if (value == null || value <= 0) return;
              Navigator.of(context).pop(value);
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  void _changeQuantity(CartLine line, int delta) {
    setState(() {
      line.quantity += delta;
      if (line.quantity <= 0) _cart.remove(line);
    });
  }

  int _quantityInCart(String productId) => _cart
      .where((l) => l.product.id == productId)
      .fold(0, (sum, l) => sum + l.quantity);

  Future<void> _checkout() async {
    if (_cart.isEmpty) return;
    final total = _subtotal;
    // Bières/Vins/Sucreries -> N° de la commande ; Poulets/Poissons/Plats
    // africains -> N° de marché (voir docs/api/pos.md) — un seul champ de
    // chaque affiché si le panier contient au moins un produit du groupe
    // concerné, jamais par ligne.
    final hasCasePricingItems = _cart.any((l) => l.product.hasCasePricing);
    final hasVariablePricingItems = _cart.any((l) => l.product.hasVariablePricing);
    final outcome = await showPaymentDialog(
      context,
      total: total,
      showOrderNumberField: hasCasePricingItems,
      showMarketNumberField: hasVariablePricingItems,
      fetchLastOrderNumber: hasCasePricingItems ? _pos.lastOrderNumber : null,
      fetchLastMarketNumber: hasVariablePricingItems ? _pos.lastMarketNumber : null,
    );
    if (outcome == null) return;

    final saleId = const Uuid().v4();
    final items = _cart
        .map(
          (l) => {
            'productId': l.product.id,
            'quantity': l.quantity,
            if (l.manualUnitPrice != null) 'unitPrice': l.manualUnitPrice,
          },
        )
        .toList();
    final payments = outcome.lines
        .map((p) => {'method': p.method, 'amount': p.amount})
        .toList();

    setState(() => _isCharging = true);
    try {
      final sale = await _pos.createSale(
        id: saleId,
        items: items,
        payments: payments,
        orderNumber: outcome.orderNumber,
        marketNumber: outcome.marketNumber,
      );
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _future = _load();
      });
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => ReceiptPage(sale: sale)));
    } on ApiException catch (e) {
      // A real business rejection (bad request, insufficient stock, ...) —
      // replaying it later wouldn't help, so it is never queued offline.
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      // No HTTP response at all reached us — treat as offline and queue the
      // sale for later sync (prompt maître §25), using saleId as the
      // idempotency key so a retry can never double-charge stock.
      await _syncQueue.enqueue(
        PendingOperation(
          id: saleId,
          entityType: 'sale',
          deviceId: await getDeviceId(),
          payload: {
            'items': items,
            'payments': payments,
            'orderNumber': ?outcome.orderNumber,
            'marketNumber': ?outcome.marketNumber,
          },
          createdAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      setState(() => _cart.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hors ligne : vente enregistrée localement, elle sera synchronisée automatiquement.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isCharging = false);
    }
  }

  void _openCartSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => CartPanel<CartLine>(
          lines: _cart,
          nameOf: (l) => l.product.name,
          quantityOf: (l) => l.quantity.toDouble(),
          unitPriceOf: (l) => l.unitPrice,
          subtotal: _subtotal,
          isCharging: _isCharging,
          onChangeQuantity: (line, delta) => setState(() {
            _changeQuantity(line, delta);
            if (_cart.isEmpty) Navigator.of(sheetContext).maybePop();
          }),
          onCheckout: () async {
            Navigator.of(sheetContext).pop();
            await _checkout();
          },
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Caisse')),
      body: Column(
        children: [
          SyncStatusBar(syncQueue: _syncQueue),
          Expanded(
            child: FutureBuilder<(List<Category>, List<Product>)>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  final message = snapshot.error is ApiException
                      ? (snapshot.error as ApiException).message
                      : '${snapshot.error}';
                  return Center(child: Text(message));
                }

                final (categories, allProducts) = snapshot.data!;
                final products = allProducts.where((p) {
                  final matchesSearch =
                      _search.isEmpty ||
                      p.name.toLowerCase().contains(_search.toLowerCase());
                  final matchesCategory =
                      _categoryId == null || p.categoryId == _categoryId;
                  return matchesSearch &&
                      matchesCategory &&
                      p.status == 'active';
                }).toList();

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < _kMobileBreakpoint;
                    final grid = ProductGrid(
                      repository: _catalog,
                      categories: categories,
                      products: products,
                      search: _search,
                      categoryId: _categoryId,
                      quantityInCart: _quantityInCart,
                      onSearchChanged: (value) =>
                          setState(() => _search = value),
                      onCategoryChanged: (value) =>
                          setState(() => _categoryId = value),
                      onProductTap: _addToCart,
                      crossAxisExtent: isMobile ? 130 : 160,
                    );

                    if (!isMobile) {
                      return Row(
                        children: [
                          Expanded(flex: 3, child: grid),
                          const VerticalDivider(width: 1),
                          Expanded(
                            flex: 2,
                            child: CartPanel<CartLine>(
                              lines: _cart,
                              nameOf: (l) => l.product.name,
                              quantityOf: (l) => l.quantity.toDouble(),
                              unitPriceOf: (l) => l.unitPrice,
                              subtotal: _subtotal,
                              isCharging: _isCharging,
                              onChangeQuantity: (line, delta) =>
                                  _changeQuantity(line, delta),
                              onCheckout: _checkout,
                            ),
                          ),
                        ],
                      );
                    }

                    return Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 64),
                          child: grid,
                        ),
                        if (_cart.isNotEmpty)
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: FloatingCartBar(
                              itemCount: _itemCount,
                              total: _subtotal,
                              onTap: _openCartSheet,
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
