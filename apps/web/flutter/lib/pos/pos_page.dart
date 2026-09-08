import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../catalog/catalog_cache.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../customers/customers_repository.dart';
import '../sync/device_id.dart';
import '../sync/pending_operation.dart';
import '../sync/sync_queue_service.dart';
import '../sync/sync_status_bar.dart';
import 'payment_dialog.dart';
import 'pos_models.dart';
import 'pos_repository.dart';
import 'receipt_page.dart';

class PosPage extends StatefulWidget {
  const PosPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  late final CatalogRepository _catalog = CatalogRepository(ApiClient(), widget.establishmentId);
  late final PosRepository _pos = PosRepository(ApiClient(), widget.establishmentId);
  late final CatalogCache _cache = CatalogCache(widget.establishmentId);
  late final SyncQueueService _syncQueue = SyncQueueService(ApiClient(), widget.establishmentId);
  late final CustomersRepository _customers = CustomersRepository(ApiClient(), widget.establishmentId);
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

  Future<void> _addToCart(Product product) async {
    // Catégorie à prix variable (ex. Poulets/Poissons/Plats africains) :
    // aucun prix par défaut à proposer — le caissier le saisit à chaque
    // ajout, une ligne distincte par prix saisi (deux pièces de poulet
    // peuvent valoir des prix différents le même jour).
    if (product.salePrice == null) {
      final price = await _promptManualPrice(product);
      if (price == null) return;
      setState(() => _cart.add(CartLine(product: product, quantity: 1, manualUnitPrice: price)));
      return;
    }
    setState(() {
      final existing = _cart.where((l) => l.product.id == product.id).firstOrNull;
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
            final value = double.tryParse(controller.text.trim().replaceAll(',', '.'));
            if (value != null && value > 0) Navigator.of(context).pop(value);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim().replaceAll(',', '.'));
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

  Future<void> _checkout() async {
    if (_cart.isEmpty) return;
    final total = _subtotal;
    final outcome = await showPaymentDialog(context, total: total, customersRepository: _customers);
    if (outcome == null) return;

    final saleId = const Uuid().v4();
    final items = _cart
        .map((l) => {
              'productId': l.product.id,
              'quantity': l.quantity,
              if (l.manualUnitPrice != null) 'unitPrice': l.manualUnitPrice,
            })
        .toList();
    final payments = outcome.lines.map((p) => {'method': p.method, 'amount': p.amount}).toList();

    setState(() => _isCharging = true);
    try {
      final sale = await _pos.createSale(id: saleId, items: items, payments: payments, customerId: outcome.customerId);
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _future = _load();
      });
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReceiptPage(sale: sale)));
    } on ApiException catch (e) {
      // A real business rejection (bad request, insufficient stock, ...) —
      // replaying it later wouldn't help, so it is never queued offline.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      // No HTTP response at all reached us — treat as offline and queue the
      // sale for later sync (prompt maître §25), using saleId as the
      // idempotency key so a retry can never double-charge stock.
      await _syncQueue.enqueue(PendingOperation(
        id: saleId,
        entityType: 'sale',
        deviceId: await getDeviceId(),
        payload: {'items': items, 'payments': payments},
        createdAt: DateTime.now(),
      ));
      if (!mounted) return;
      setState(() => _cart.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hors ligne : vente enregistrée localement, elle sera synchronisée automatiquement.')),
      );
    } finally {
      if (mounted) setState(() => _isCharging = false);
    }
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
            final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : '${snapshot.error}';
            return Center(child: Text(message));
          }

          final (categories, allProducts) = snapshot.data!;
          final products = allProducts.where((p) {
            final matchesSearch = _search.isEmpty || p.name.toLowerCase().contains(_search.toLowerCase());
            final matchesCategory = _categoryId == null || p.categoryId == _categoryId;
            return matchesSearch && matchesCategory && p.status == 'active';
          }).toList();

          return Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: TextField(
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Rechercher un produit'),
                        onChanged: (value) => setState(() => _search = value),
                      ),
                    ),
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(label: const Text('Tous'), selected: _categoryId == null, onSelected: (_) => setState(() => _categoryId = null)),
                          ),
                          for (final category in categories)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: ChoiceChip(
                                label: Text(category.name),
                                selected: _categoryId == category.id,
                                onSelected: (_) => setState(() => _categoryId = category.id),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 160, mainAxisExtent: 150),
                        itemCount: products.length,
                        itemBuilder: (context, index) {
                          final product = products[index];
                          return _PosProductTile(product: product, repository: _catalog, onTap: () => _addToCart(product));
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    Expanded(
                      child: _cart.isEmpty
                          ? const Center(child: Text('Panier vide'))
                          : ListView(
                              children: [
                                for (final line in _cart)
                                  ListTile(
                                    title: Text(line.product.name),
                                    subtitle: Text('${line.unitPrice.toStringAsFixed(0)} FCFA x ${line.quantity}'),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => _changeQuantity(line, -1)),
                                        Text('${line.quantity}'),
                                        IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => _changeQuantity(line, 1)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                              const Spacer(),
                              Text('${_subtotal.toStringAsFixed(0)} FCFA', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _cart.isEmpty || _isCharging ? null : _checkout,
                            child: _isCharging
                                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('Encaisser'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
            ),
          ),
        ],
      ),
    );
  }
}

class _PosProductTile extends StatelessWidget {
  const _PosProductTile({required this.product, required this.repository, required this.onTap});

  final Product product;
  final CatalogRepository repository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primaryImage = product.images.where((i) => i.isPrimary).firstOrNull ?? product.images.firstOrNull;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: primaryImage == null
                  ? const ColoredBox(color: Color(0x11000000), child: Icon(Icons.local_drink_outlined, size: 28))
                  : FutureBuilder<String>(
                      future: repository.getImageUrl(product.id, primaryImage.id, variant: 'thumbnail'),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const ColoredBox(color: Color(0x11000000));
                        return ColoredBox(
                          color: const Color(0x11000000),
                          child: Image.network(snapshot.data!, fit: BoxFit.contain),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                  Text(product.salePrice != null ? '${product.salePrice!.toStringAsFixed(0)} FCFA' : 'Prix variable'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
