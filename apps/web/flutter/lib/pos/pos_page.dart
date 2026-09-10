import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../catalog/catalog_cache.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../common/formatting.dart';
import '../sync/device_id.dart';
import '../sync/pending_operation.dart';
import '../sync/sync_queue_service.dart';
import '../sync/sync_status_bar.dart';
import '../theme/app_theme.dart';
import 'payment_dialog.dart';
import 'pos_models.dart';
import 'pos_repository.dart';
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
    final outcome = await showPaymentDialog(context, total: total);
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
          payload: {'items': items, 'payments': payments},
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
        builder: (context, scrollController) => _CartPanel(
          cart: _cart,
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
                    final grid = _ProductGrid(
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
                            child: _CartPanel(
                              cart: _cart,
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
                            child: _FloatingCartBar(
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

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({
    required this.repository,
    required this.categories,
    required this.products,
    required this.search,
    required this.categoryId,
    required this.quantityInCart,
    required this.onSearchChanged,
    required this.onCategoryChanged,
    required this.onProductTap,
    required this.crossAxisExtent,
  });

  final CatalogRepository repository;
  final List<Category> categories;
  final List<Product> products;
  final String search;
  final String? categoryId;
  final int Function(String productId) quantityInCart;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<Product> onProductTap;
  final double crossAxisExtent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Rechercher un produit',
              isDense: true,
            ),
            onChanged: onSearchChanged,
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: const Text('Tous'),
                  selected: categoryId == null,
                  onSelected: (_) => onCategoryChanged(null),
                ),
              ),
              for (final category in categories)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(category.name),
                    selected: categoryId == category.id,
                    onSelected: (_) => onCategoryChanged(category.id),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: crossAxisExtent,
              mainAxisExtent: 132,
            ),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return _PosProductTile(
                product: product,
                repository: repository,
                quantityInCart: quantityInCart(product.id),
                onTap: () => onProductTap(product),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FloatingCartBar extends StatelessWidget {
  const _FloatingCartBar({
    required this.itemCount,
    required this.total,
    required this.onTap,
  });

  final int itemCount;
  final double total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Material(
          color: AppColors.green,
          borderRadius: BorderRadius.circular(14),
          elevation: 3,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Icon(
                    Icons.shopping_cart,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$itemCount article${itemCount > 1 ? 's' : ''} · ${formatAmount(total)} FCFA',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Voir le panier',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Contenu du panier — partagé entre la colonne latérale (tablette/desktop)
/// et la feuille modale inférieure (mobile), même état et mêmes actions.
class _CartPanel extends StatelessWidget {
  const _CartPanel({
    required this.cart,
    required this.subtotal,
    required this.isCharging,
    required this.onChangeQuantity,
    required this.onCheckout,
    this.scrollController,
  });

  final List<CartLine> cart;
  final double subtotal;
  final bool isCharging;
  final void Function(CartLine line, int delta) onChangeQuantity;
  final VoidCallback onCheckout;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (scrollController != null)
          const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 4),
            child: SizedBox(width: 36, child: Divider(thickness: 4, height: 4)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              const Text(
                'Panier',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const Spacer(),
              if (scrollController != null)
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
            ],
          ),
        ),
        Expanded(
          child: cart.isEmpty
              ? const Center(child: Text('Panier vide'))
              : ListView(
                  controller: scrollController,
                  children: [
                    for (final line in cart)
                      ListTile(
                        title: Text(line.product.name),
                        subtitle: Text(
                          '${formatAmount(line.unitPrice)} FCFA x ${line.quantity}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: AppColors.alert,
                              ),
                              onPressed: () => onChangeQuantity(line, -1),
                            ),
                            Text('${line.quantity}'),
                            IconButton(
                              icon: const Icon(
                                Icons.add_circle_outline,
                                color: AppColors.green,
                              ),
                              onPressed: () => onChangeQuantity(line, 1),
                            ),
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
                  const Text(
                    'Total',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const Spacer(),
                  Text(
                    '${formatAmount(subtotal)} FCFA',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: cart.isEmpty || isCharging ? null : onCheckout,
                child: isCharging
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Encaisser'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PosProductTile extends StatelessWidget {
  const _PosProductTile({
    required this.product,
    required this.repository,
    required this.quantityInCart,
    required this.onTap,
  });

  final Product product;
  final CatalogRepository repository;
  final int quantityInCart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primaryImage =
        product.images.where((i) => i.isPrimary).firstOrNull ??
        product.images.firstOrNull;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: primaryImage == null
                      ? const ColoredBox(
                          color: AppColors.greenLight,
                          child: Icon(
                            Icons.local_drink_outlined,
                            size: 26,
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
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13),
                      ),
                      Text(
                        product.salePrice != null
                            ? '${formatAmount(product.salePrice!)} FCFA'
                            : 'Prix variable',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (quantityInCart > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.orange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$quantityInCart',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
