import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../catalog/catalog_cache.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../common/formatting.dart';
import '../common/offline_banner.dart';
import '../common/read_cache.dart';
import '../pos/cart_panel.dart';
import '../pos/category_sold_items_page.dart';
import '../pos/payment_dialog.dart';
import '../pos/pos_repository.dart';
import '../pos/product_grid.dart';
import '../pos/receipt_page.dart';
import '../sync/connectivity_status.dart';
import '../sync/device_id.dart';
import '../sync/offline_sale.dart';
import '../sync/pending_operation.dart';
import '../sync/sync_queue_service.dart';
import '../theme/app_theme.dart';
import 'offline_orders.dart';
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
    required this.roleName,
    required this.tableId,
  });

  final TablesRepository repository;
  final String establishmentId;
  final String roleName;
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
  late final SyncQueueService _syncQueue = SyncQueueService(
    ApiClient(),
    widget.establishmentId,
  );

  Future<Cached<List<OrderDetail>>>? _ordersFuture;
  // Date de la copie locale servie à la place du serveur injoignable (nul :
  // données fraîches) — voir `TablesRepository.loadOpenOrders`.
  DateTime? _ordersCachedAt;
  StreamSubscription<bool>? _reconnectSubscription;
  Future<(List<Category>, List<Product>)>? _catalogFuture;
  // Copie synchrone du catalogue chargé par `_catalogFuture`, pour que
  // `_changeQuantity` retrouve le `Product` d'une ligne (prix de référence,
  // nom) sans dépendre du `FutureBuilder` de `build()` — voir
  // `_promptManualPrice`, appelé depuis le "+" d'une ligne à prix de
  // référence variable.
  List<Product> _allProducts = [];
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
    SyncQueueService.syncCompleted.addListener(_onSyncCompleted);
    _reconnectSubscription = ConnectivityStatus.onReconnect(() {
      if (mounted && _ordersCachedAt != null) {
        _reloadOrders();
        setState(() {
          _catalogFuture = _loadCatalog()..ignore();
        });
      }
    });
  }

  @override
  void dispose() {
    _reconnectSubscription?.cancel();
    SyncQueueService.syncCompleted.removeListener(_onSyncCompleted);
    super.dispose();
  }

  // Les saisies faites hors ligne viennent de partir : l'addition affichée
  // redevient celle du serveur (mêmes identifiants, aucune ligne perdue).
  void _onSyncCompleted() {
    if (mounted && _ordersCachedAt != null) _reloadOrders();
  }

  Future<(List<Category>, List<Product>)> _loadCatalog() async {
    final cache = CatalogCache(widget.establishmentId);
    try {
      final categories = await _catalog.listCategories();
      final products = await _catalog.listProducts();
      _allProducts = products;
      try {
        await cache.save(categories, products);
      } catch (_) {
        // Stockage indisponible : le catalogue en ligne reste valable.
      }
      return (categories, products);
    } catch (error) {
      // Serveur injoignable : dernier catalogue connu (même copie que la
      // Caisse), jamais pour un rejet métier du serveur.
      if (!isNetworkFailure(error)) rethrow;
      final cached = await cache.load();
      if (cached == null) rethrow;
      _allProducts = cached.$2;
      return cached;
    }
  }

  void _reloadOrders() {
    // Ne pas réinitialiser _selectedOrderId ici : un ajout/retrait sur
    // l'addition 2 ne doit pas ramener l'écran sur l'addition 1 — build()
    // retombe déjà sur l'index 0 si l'addition sélectionnée a disparu.
    final future = widget.repository.loadOpenOrders(widget.tableId).then((result) {
      _ordersCachedAt = result.cachedAt;
      return result;
    });
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
      try {
        await widget.repository.openAdditionalOrder(widget.tableId);
        final orders = await widget.repository.listOpenOrdersForTable(
          widget.tableId,
        );
        if (!mounted) return;
        setState(() {
          _ordersCachedAt = null;
          _ordersFuture = Future.value(Cached(orders));
          _selectedOrderId = orders.last.id;
        });
        return;
      } catch (error) {
        if (!_shouldQueue(error)) rethrow;
      }
      // Hors ligne : nouvelle addition créée sur l'appareil, envoyée à la
      // reconnexion (`order_open` sur une table déjà occupée).
      final order = await _offline.openOrder(widget.tableId);
      if (!mounted) return;
      _selectedOrderId = order.id;
      _reloadOrders();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hors ligne : nouvelle addition créée localement, elle sera enregistrée à la reconnexion.'),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Erreur — nouvelle addition non créée"),
        ),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  /// Vrai quand l'échec indique un serveur injoignable (aucune réponse, ou
  /// passerelle indisponible) : la saisie est alors gardée sur l'appareil et
  /// mise en file plutôt que refusée. Un vrai rejet du serveur reste une erreur.
  bool _shouldQueue(Object error) => isNetworkFailure(error);

  late final OfflineOrders _offline = OfflineOrders(
    repository: widget.repository,
    queue: _syncQueue,
  );

  /// Applique une modification d'addition : directement sur le serveur si
  /// l'addition y existe et que le réseau répond, sinon sur l'appareil
  /// ([offline]). Une addition qui porte des saisies pas encore synchronisées
  /// ([OrderDetail.pendingSync]) passe TOUJOURS par la file : le serveur ne
  /// connaît pas encore ses changements, ni peut-être l'addition elle-même.
  Future<void> _mutate({
    required OrderDetail order,
    required Future<void> Function() online,
    required Future<void> Function() offline,
    required String failureMessage,
  }) async {
    setState(() => _isBusy = true);
    try {
      if (order.pendingSync) {
        await offline();
      } else {
        try {
          await online();
        } catch (error) {
          if (!_shouldQueue(error)) rethrow;
          await offline();
        }
      }
      _reloadOrders();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failureMessage)),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  /// Pour un produit à prix fixe "classique" (ex. Poulets/Poissons/Plats
  /// africains) : saisie du prix de vente. Pour un produit à prix de
  /// référence variable (`referenceSalePrice` non nul, ex. Gbêlê) : saisie
  /// du MONTANT payé, avec aperçu de la quantité (litres) — même dialogue
  /// qu'en Caisse (`pos_page.dart._promptManualPrice`), voir docs/api/pos.md.
  Future<double?> _promptManualPrice(Product product, {double? initialAmount}) async {
    final referencePrice = product.referenceSalePrice;
    final controller = TextEditingController(
      text: initialAmount != null ? initialAmount.round().toString() : '',
    );
    // Le montant reconduit est présélectionné : un tapotement sur "Ajouter"
    // le reprend tel quel, ou l'utilisateur tape directement un nouveau
    // montant pour l'écraser (ex. versement suivant à un prix différent).
    controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length);
    return showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final amount = double.tryParse(controller.text.trim().replaceAll(',', '.'));
          return AlertDialog(
            title: Text(
              referencePrice != null ? 'Montant payé — ${product.name}' : 'Prix de vente — ${product.name}',
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: referencePrice != null ? 'Montant (FCFA)' : 'Prix (FCFA)',
                helperText: referencePrice != null && amount != null && amount > 0
                    ? '≈ ${(amount / referencePrice).toStringAsFixed(2)} L'
                    : null,
              ),
              onChanged: (_) => setDialogState(() {}),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: (amount == null || amount <= 0) ? null : () => Navigator.of(context).pop(amount),
                child: const Text('Ajouter'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// `null` : dialogue annulé. `true` : vente à l'unité (`unitSalePrice`).
  /// `false` : tarif normal (`salePrice`). Même dialogue qu'en Caisse
  /// (`PosPage._promptPackOrUnit`).
  Future<bool?> _promptPackOrUnit(Product product) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(product.name),
        content: const Text('Comment vendre ce produit ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              '${product.unit?.trim().isNotEmpty == true ? 'Lot (${product.unit})' : 'Lot'} — '
              '${formatAmount(product.salePrice!)} FCFA',
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Unité — ${formatAmount(product.unitSalePrice!)} FCFA'),
          ),
        ],
      ),
    );
  }

  Future<void> _addProduct(OrderDetail order, Product product) async {
    // Ignore les taps pendant qu'une mutation est déjà en cours : sans ça,
    // un double-tap sur une tuile pendant l'aller-retour réseau envoie deux
    // requêtes d'ajout avant que la première n'ait rechargé l'addition.
    if (_isBusy) return;
    // Catégorie à prix variable (Poulets/Poissons/Plats africains) : aucun
    // prix catalogue à proposer, le serveur exige `unitPrice` — même règle
    // qu'en Caisse (`pos_page.dart`). Produit à prix de référence variable
    // (`referenceSalePrice` non nul, ex. Gbêlê) : le montant saisi part en
    // `amountPaid`, jamais `unitPrice` — voir docs/api/pos.md (2026-09-24).
    double? unitPrice;
    double? amountPaid;
    if (product.salePrice == null) {
      final amount = await _promptManualPrice(product);
      if (amount == null) return;
      if (product.referenceSalePrice != null) {
        amountPaid = amount;
      } else {
        unitPrice = amount;
      }
    }
    // Vente à l'unité en plus du tarif normal (ex. Heineken 33/Despé 33) —
    // même mécanisme qu'en Caisse (`pos_page.dart`).
    var sellAsUnit = false;
    if (product.unitSalePrice != null) {
      final choice = await _promptPackOrUnit(product);
      if (choice == null) return;
      sellAsUnit = choice;
    }
    await _mutate(
      order: order,
      online: () => widget.repository.addItem(
        order.id,
        productId: product.id,
        quantity: 1,
        unitPrice: unitPrice,
        amountPaid: amountPaid,
        sellAsUnit: sellAsUnit,
      ),
      offline: () => _offline.addItem(
        widget.tableId,
        order,
        product,
        unitPrice: unitPrice,
        amountPaid: amountPaid,
        sellAsUnit: sellAsUnit,
      ),
      failureMessage: 'Erreur — article non ajouté',
    );
  }

  Future<void> _changeQuantity(
    OrderDetail order,
    OrderItemDetail item,
    int delta,
  ) async {
    // Même garde que _addProduct : CartPanel désactive déjà ses boutons
    // +/- pendant isCharging, ce return est la deuxième ligne de défense.
    if (_isBusy) return;

    // Prix de référence variable (ex. Gbêlê) : `quantity` est une fraction
    // (litres) déduite d'un montant payé, pas un compte d'unités — un "+1"
    // brut ajouterait ~1 L (le prix de référence entier, ex. 3 333 FCFA) au
    // lieu de reconduire le montant payé (ex. 100 FCFA). "+" rouvre donc le
    // dialogue de montant, pré-rempli avec ce qui a déjà été payé sur cette
    // ligne ; "−" retire la ligne entière, faute de pouvoir isoler "un
    // versement" dans une quantité fusionnée (décision utilisateur du
    // 2026-09-26).
    if (item.referenceSalePrice != null) {
      if (delta > 0) {
        final product = _allProducts.where((p) => p.id == item.productId).firstOrNull;
        if (product == null) return;
        final amount = await _promptManualPrice(
          product,
          initialAmount: item.quantity * item.unitPrice,
        );
        if (amount == null) return;
        await _mutate(
          order: order,
          online: () => widget.repository.addItem(
            order.id,
            productId: item.productId,
            quantity: 1,
            amountPaid: amount,
          ),
          offline: () => _offline.addItem(widget.tableId, order, product, amountPaid: amount),
          failureMessage: 'Erreur — article non ajouté',
        );
        return;
      }
      await _mutate(
        order: order,
        online: () => widget.repository.removeItem(order.id, item.id),
        offline: () => _offline.removeItem(widget.tableId, order, item),
        failureMessage: 'Erreur — article non retiré',
      );
      return;
    }

    final nextQuantity = item.quantity + delta;
    await _mutate(
      order: order,
      online: () => nextQuantity <= 0
          ? widget.repository.removeItem(order.id, item.id)
          : widget.repository.updateItemQuantity(order.id, item.id, nextQuantity),
      offline: () => _offline.setQuantity(widget.tableId, order, item, nextQuantity),
      failureMessage: 'Erreur — quantité non modifiée',
    );
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
      allowDateEntry: canSetSaleDate(widget.roleName),
      fetchLastOrderNumber: hasCasePricingItems ? _pos.lastOrderNumber : null,
      fetchLastMarketNumber: hasVariablePricingItems
          ? _pos.lastMarketNumber
          : null,
    );
    if (outcome == null) return;

    final saleId = const Uuid().v4();
    // `unitPrice` est repris de la ligne d'addition : indispensable pour un
    // produit à prix variable (`SalesService.create` refuse la vente sans
    // lui), ignoré côté serveur pour un produit à prix fixe dont le prix
    // catalogue prévaut toujours.
    final items = order.items
        .map(
          (i) => {
            'productId': i.productId,
            'quantity': i.quantity,
            'unitPrice': i.unitPrice,
            if (i.sellAsUnit) 'sellAsUnit': true,
          },
        )
        .toList();
    final payments = outcome.lines
        .map((p) => {'method': p.method, 'amount': p.amount})
        .toList();

    // Addition qui n'existe pas (ou pas entièrement) côté serveur : encaissement
    // directement mis en file, il partira APRÈS son ouverture et ses articles.
    if (order.pendingSync) {
      setState(() => _isBusy = true);
      try {
        await _checkoutOffline(order, saleId, items, payments, outcome);
      } finally {
        if (mounted) setState(() => _isBusy = false);
      }
      return;
    }

    setState(() => _isBusy = true);
    try {
      final sale = await _pos.createSale(
        id: saleId,
        items: items,
        payments: payments,
        orderId: order.id,
        tableId: widget.tableId,
        source: 'table',
        orderNumber: outcome.orderNumber,
        marketNumber: outcome.marketNumber,
        createdAt: outcome.date,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ReceiptPage(sale: sale)),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      if (isNetworkFailure(e)) {
        // Passerelle indisponible (502/503/504) : pas de réponse du serveur.
        await _checkoutOffline(order, saleId, items, payments, outcome);
        return;
      }
      // Rejet métier réel (ex. addition déjà clôturée, paiement invalide) —
      // rejouer ne changerait rien, jamais mis en file.
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      // Aucune réponse HTTP reçue — coupure réseau.
      if (!mounted) return;
      await _checkoutOffline(order, saleId, items, payments, outcome);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  /// Même traitement que `PosPage._checkout` hors ligne : mise en file avec
  /// `saleId` comme clé d'idempotence, rejouée plus tard via SyncService
  /// (`entityType: 'sale'`, qui gère déjà orderId/tableId/source — voir
  /// docs/api/sync.md). L'addition reste ouverte côté serveur jusqu'à la
  /// synchronisation ; on quitte l'écran pour éviter un second encaissement
  /// accidentel sur la même addition avant que la file n'ait pu être vidée.
  Future<void> _checkoutOffline(
    OrderDetail order,
    String saleId,
    List<Map<String, dynamic>> items,
    List<Map<String, dynamic>> payments,
    PaymentOutcome outcome,
  ) async {
    await _syncQueue.enqueue(
      PendingOperation(
        id: saleId,
        entityType: 'sale',
        deviceId: await getDeviceId(),
        payload: {
          'items': items,
          'payments': payments,
          'orderId': order.id,
          'tableId': widget.tableId,
          'source': 'table',
          'orderNumber': ?outcome.orderNumber,
          'marketNumber': ?outcome.marketNumber,
          'createdAt': ?outcome.date?.toUtc().toIso8601String(),
        },
        createdAt: DateTime.now(),
      ),
    );
    // Stock local décrémenté dans le cache du catalogue (pas d'avertissement
    // ici : cet écran ne charge pas le stock des produits) et reçu établi sur
    // l'appareil, à titre provisoire.
    await CatalogCache(widget.repository.establishmentId).applyStockDecrements(
      stockNeeded(
        order.items.map((i) => (productId: i.productId, quantity: i.quantity)),
      ),
    );
    // Addition retirée de la copie locale (et table mise à jour) : sinon
    // l'écran proposerait d'encaisser une seconde fois la même addition.
    await widget.repository.markOrderCheckedOutLocally(widget.tableId, order);
    final receipt = provisionalSale(
      id: saleId,
      createdAt: outcome.date ?? DateTime.now(),
      lines: [
        for (final i in order.items)
          ProvisionalLine(
            productId: i.productId,
            name: i.productName,
            quantity: i.quantity,
            unitPrice: i.unitPrice,
          ),
      ],
      payments: outcome.lines
          .map((p) => (method: p.method, amount: p.amount))
          .toList(),
      orderNumber: outcome.orderNumber,
      marketNumber: outcome.marketNumber,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Hors ligne : encaissement enregistré localement, il sera synchronisé automatiquement.',
        ),
      ),
    );
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ReceiptPage(sale: receipt, provisional: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Addition'),
        actions: [
          IconButton(
            tooltip: 'Boissons vendues',
            icon: const Icon(Icons.local_bar_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CategorySoldItemsPage.boissons(
                  establishmentId: widget.establishmentId,
                  roleName: widget.roleName,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Plats vendus',
            icon: const Icon(Icons.restaurant_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CategorySoldItemsPage.plats(
                  establishmentId: widget.establishmentId,
                  roleName: widget.roleName,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Nouvelle addition',
            icon: const Icon(Icons.add_box_outlined),
            onPressed: _isBusy ? null : _addNewAddition,
          ),
        ],
      ),
      body: FutureBuilder<Cached<List<OrderDetail>>>(
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
          final cachedAt = ordersSnapshot.data!.cachedAt;
          final orders = ordersSnapshot.data!.value;
          if (orders.isEmpty) {
            // Possible depuis la copie locale : la dernière addition de la table
            // vient d'être encaissée hors ligne.
            return Column(
              children: [
                if (cachedAt != null) OfflineBanner(cachedAt: cachedAt, onRefresh: _reloadOrders),
                const Expanded(child: Center(child: Text('Aucune addition ouverte sur cette table.'))),
              ],
            );
          }
          final matchIndex = orders.indexWhere((o) => o.id == _selectedOrderId);
          final selectedIndex = matchIndex >= 0 ? matchIndex : 0;
          final order = orders[selectedIndex];

          return Column(
            children: [
              if (cachedAt != null) OfflineBanner(cachedAt: cachedAt, onRefresh: _reloadOrders),
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
                          isReferencePriced: (item) =>
                              item.referenceSalePrice != null,
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
