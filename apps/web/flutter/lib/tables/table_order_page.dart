import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../pos/cart_panel.dart';
import '../pos/payment_dialog.dart';
import '../pos/pos_repository.dart';
import '../pos/product_grid.dart';
import '../pos/receipt_page.dart';
import '../theme/app_theme.dart';
import 'tables_models.dart';
import 'tables_repository.dart';

/// Écran d'une table occupée : une addition (ou plusieurs, en onglets) avec
/// la grille produits + panier de la Caisse (composants partagés de `lib/pos/`).
/// Contrairement à `PosPage`, chaque ajout/retrait/changement de quantité
/// appelle le serveur immédiatement (persistance immédiate, addition visible
/// en temps réel par un autre appareil) — voir
/// docs/superpowers/specs/2026-09-10-table-order-caisse-design.md.
class TableOrderPage extends StatefulWidget {
  const TableOrderPage({
    super.key,
    required this.repository,
    required this.establishmentId,
    required this.tableId,
  });

  final TablesRepository repository;
  final String establishmentId;
  final String tableId;

  @override
  State<TableOrderPage> createState() => _TableOrderPageState();
}

class _TableOrderPageState extends State<TableOrderPage> {
  late final CatalogRepository _catalog = CatalogRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final PosRepository _pos = PosRepository(
    ApiClient(),
    widget.establishmentId,
  );

  Future<List<OrderDetail>>? _ordersFuture;
  Future<(List<Category>, List<Product>)>? _catalogFuture;
  // Sélection par identifiant d'addition plutôt que par position : si une
  // autre addition de la table est encaissée depuis un autre appareil, un
  // rechargement ne doit pas glisser silencieusement la sélection vers une
  // addition différente de celle affichée à l'écran.
  String? _selectedOrderId;
  String _search = '';
  String? _categoryId;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    // `..ignore()` : même garde que les autres écrans de ce module contre un
    // rejet "unhandled" en test (flutter_test répond quasi instantanément,
    // voir stock_lots_tab.dart pour le même motif).
    _catalogFuture = _loadCatalog()..ignore();
    _reloadOrders();
  }

  Future<(List<Category>, List<Product>)> _loadCatalog() async {
    final categories = await _catalog.listCategories();
    final products = await _catalog.listProducts();
    return (categories, products);
  }

  void _reloadOrders() {
    // Ne pas réinitialiser _selectedOrderId ici : un ajout/retrait sur
    // l'addition 2 ne doit pas ramener l'écran sur l'addition 1 — build()
    // retombe déjà sur l'index 0 si l'addition sélectionnée a disparu.
    final future = widget.repository.listOpenOrdersForTable(widget.tableId);
    future.ignore();
    // Corps bloc (pas `=>`) : une closure fléchée affectant un champ `Future`
    // renvoie la valeur de l'affectation, donc le `Future` lui-même — setState
    // le prendrait alors pour une closure `async` et lève une assertion (même
    // piège que stock_lots_tab.dart plus tôt dans cette session).
    setState(() {
      _ordersFuture = future;
    });
  }

  Future<void> _addNewAddition() async {
    setState(() => _isBusy = true);
    try {
      await widget.repository.openAdditionalOrder(widget.tableId);
      final orders = await widget.repository.listOpenOrdersForTable(
        widget.tableId,
      );
      if (!mounted) return;
      setState(() {
        _ordersFuture = Future.value(orders);
        _selectedOrderId = orders.last.id;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Erreur réseau — nouvelle addition non créée"),
        ),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
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

  Future<void> _addProduct(OrderDetail order, Product product) async {
    // Catégorie à prix variable (Poulets/Poissons/Plats africains) : aucun
    // prix catalogue à proposer, le serveur exige `unitPrice` — même règle
    // qu'en Caisse (`pos_page.dart`).
    double? unitPrice;
    if (product.salePrice == null) {
      unitPrice = await _promptManualPrice(product);
      if (unitPrice == null) return;
    }
    setState(() => _isBusy = true);
    try {
      await widget.repository.addItem(
        order.id,
        productId: product.id,
        quantity: 1,
        unitPrice: unitPrice,
      );
      _reloadOrders();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur réseau — article non ajouté')),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _changeQuantity(
    OrderDetail order,
    OrderItemDetail item,
    int delta,
  ) async {
    final nextQuantity = item.quantity + delta;
    setState(() => _isBusy = true);
    try {
      if (nextQuantity <= 0) {
        await widget.repository.removeItem(order.id, item.id);
      } else {
        await widget.repository.updateItemQuantity(
          order.id,
          item.id,
          nextQuantity,
        );
      }
      _reloadOrders();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur réseau — quantité non modifiée')),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _checkout(OrderDetail order) async {
    if (order.items.isEmpty) return;
    // Bières/Vins/Sucreries -> N° de la commande ; Poulets/Poissons/Plats
    // africains -> N° de marché — un seul champ de chaque, affiché si
    // l'addition contient au moins un produit du groupe concerné.
    final hasCasePricingItems = order.items.any((i) => i.hasCasePricing);
    final hasVariablePricingItems = order.items.any(
      (i) => i.hasVariablePricing,
    );
    final outcome = await showPaymentDialog(
      context,
      total: order.total,
      showOrderNumberField: hasCasePricingItems,
      showMarketNumberField: hasVariablePricingItems,
      fetchLastOrderNumber: hasCasePricingItems ? _pos.lastOrderNumber : null,
      fetchLastMarketNumber: hasVariablePricingItems
          ? _pos.lastMarketNumber
          : null,
    );
    if (outcome == null) return;

    setState(() => _isBusy = true);
    try {
      final sale = await _pos.createSale(
        // `unitPrice` est repris de la ligne d'addition : indispensable pour
        // un produit à prix variable (`SalesService.create` refuse la vente
        // sans lui), ignoré côté serveur pour un produit à prix fixe dont le
        // prix catalogue prévaut toujours.
        items: order.items
            .map(
              (i) => {
                'productId': i.productId,
                'quantity': i.quantity,
                'unitPrice': i.unitPrice,
              },
            )
            .toList(),
        payments: outcome.lines
            .map((p) => {'method': p.method, 'amount': p.amount})
            .toList(),
        orderId: order.id,
        tableId: widget.tableId,
        source: 'table',
        orderNumber: outcome.orderNumber,
        marketNumber: outcome.marketNumber,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ReceiptPage(sale: sale)),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      // Contrairement à PosPage, une vente de table n'est pas mise en file
      // hors ligne ici : la vente référence une addition serveur précise
      // (orderId) qu'il faut d'abord confirmer encore ouverte au retour du
      // réseau — hors périmètre de cette tâche, voir docs/superpowers/specs.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Erreur réseau — encaissement non enregistré, réessayez',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Addition'),
        actions: [
          IconButton(
            tooltip: 'Nouvelle addition',
            icon: const Icon(Icons.add_box_outlined),
            onPressed: _isBusy ? null : _addNewAddition,
          ),
        ],
      ),
      body: FutureBuilder<List<OrderDetail>>(
        future: _ordersFuture,
        builder: (context, ordersSnapshot) {
          if (ordersSnapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (ordersSnapshot.hasError) {
            final message = ordersSnapshot.error is ApiException
                ? (ordersSnapshot.error as ApiException).message
                : '${ordersSnapshot.error}';
            return Center(child: Text(message));
          }
          final orders = ordersSnapshot.data!;
          final matchIndex = orders.indexWhere((o) => o.id == _selectedOrderId);
          final selectedIndex = matchIndex >= 0 ? matchIndex : 0;
          final order = orders[selectedIndex];

          return Column(
            children: [
              if (orders.length > 1)
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (var i = 0; i < orders.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text(
                              'Addition ${i + 1} (${orders[i].items.length})',
                            ),
                            selected: i == selectedIndex,
                            selectedColor: AppColors.green,
                            onSelected: (_) =>
                                setState(() => _selectedOrderId = orders[i].id),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: FutureBuilder<(List<Category>, List<Product>)>(
                  future: _catalogFuture,
                  builder: (context, catalogSnapshot) {
                    if (catalogSnapshot.connectionState !=
                        ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (catalogSnapshot.hasError) {
                      final message = catalogSnapshot.error is ApiException
                          ? (catalogSnapshot.error as ApiException).message
                          : '${catalogSnapshot.error}';
                      return Center(child: Text(message));
                    }
                    final (categories, allProducts) = catalogSnapshot.data!;
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
                        final isMobile = constraints.maxWidth < 700;
                        final grid = ProductGrid(
                          repository: _catalog,
                          categories: categories,
                          products: products,
                          search: _search,
                          categoryId: _categoryId,
                          quantityInCart: (productId) => order.items
                              .where((i) => i.productId == productId)
                              .fold(0, (sum, i) => sum + i.quantity.round()),
                          onSearchChanged: (value) =>
                              setState(() => _search = value),
                          onCategoryChanged: (value) =>
                              setState(() => _categoryId = value),
                          onProductTap: (product) =>
                              _addProduct(order, product),
                          crossAxisExtent: isMobile ? 130 : 160,
                        );
                        final cart = CartPanel<OrderItemDetail>(
                          lines: order.items,
                          nameOf: (i) => i.productName,
                          quantityOf: (i) => i.quantity,
                          unitPriceOf: (i) => i.unitPrice,
                          subtotal: order.total,
                          isCharging: _isBusy,
                          onChangeQuantity: (item, delta) =>
                              _changeQuantity(order, item, delta),
                          onCheckout: () => _checkout(order),
                        );

                        if (!isMobile) {
                          return Row(
                            children: [
                              Expanded(flex: 3, child: grid),
                              const VerticalDivider(width: 1),
                              Expanded(flex: 2, child: cart),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            Expanded(child: grid),
                            SizedBox(height: 280, child: cart),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
