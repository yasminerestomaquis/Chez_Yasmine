import 'package:uuid/uuid.dart';

import '../catalog/models.dart';
import '../sync/device_id.dart';
import '../sync/pending_operation.dart';
import '../sync/sync_queue_service.dart';
import 'tables_models.dart';
import 'tables_repository.dart';

/// Ligne d'addition telle que le serveur la calculera (`OrdersService.addItem`).
class LocalOrderLine {
  LocalOrderLine({required this.quantity, required this.unitPrice, required this.sellAsUnit});

  final double quantity;
  final double unitPrice;
  final bool sellAsUnit;
}

/// Reproduit côté appareil les règles de prix du serveur pour afficher la
/// ligne tout de suite : prix fixe (catalogue, à l'unité si demandé), prix de
/// référence variable (Gbêlê : quantité déduite du montant payé, arrondie à 2
/// décimales — `resolveReferencePriceLine`), ou prix saisi. Lève
/// [ArgumentError] si une donnée requise manque (le serveur refuserait aussi).
LocalOrderLine resolveLocalLine(
  Product product, {
  double? quantity,
  double? unitPrice,
  double? amountPaid,
  bool sellAsUnit = false,
}) {
  final fixed = product.salePrice;
  if (fixed != null) {
    if (quantity == null) throw ArgumentError('Quantité requise pour ${product.name}');
    final byUnit = sellAsUnit && product.unitSalePrice != null;
    return LocalOrderLine(
      quantity: quantity,
      unitPrice: byUnit ? product.unitSalePrice! : fixed,
      sellAsUnit: byUnit,
    );
  }
  final reference = product.referenceSalePrice;
  if (reference != null) {
    if (amountPaid == null || reference <= 0) throw ArgumentError('Montant payé requis pour ${product.name}');
    final resolvedQuantity = (amountPaid / reference * 100).round() / 100;
    if (resolvedQuantity <= 0) throw ArgumentError('Montant trop faible pour ${product.name}');
    return LocalOrderLine(quantity: resolvedQuantity, unitPrice: amountPaid / resolvedQuantity, sellAsUnit: false);
  }
  if (unitPrice == null || quantity == null) {
    throw ArgumentError('Prix de vente et quantité requis pour ${product.name}');
  }
  return LocalOrderLine(quantity: quantity, unitPrice: unitPrice, sellAsUnit: false);
}

/// Ouverture de table et modification d'une addition SANS réseau (phase 4,
/// voir docs/api/sync.md).
///
/// Chaque saisie fait deux choses : elle met l'opération en file (`order_open`,
/// `order_item_add`, `order_item_set`, `order_item_remove`, rejouées dans
/// l'ordre à la reconnexion) et elle applique le changement à la COPIE LOCALE
/// de l'addition et de la table, pour que l'écran le montre aussitôt. Les
/// identifiants (addition, ligne) sont choisis ici, ce qui rend les rejeux
/// sûrs et permet d'enchaîner ouverture, ajouts et encaissement avant même
/// que le serveur ait vu l'addition. Les écritures de quantité portent la
/// quantité que l'appareil a vue : si un autre appareil l'a changée entre-temps,
/// le serveur refuse (opération « à corriger ») au lieu d'écraser.
class OfflineOrders {
  OfflineOrders({
    required this.repository,
    required this.queue,
    Future<String> Function()? deviceId,
    String Function()? newId,
    DateTime Function()? now,
  })  : _deviceId = deviceId ?? getDeviceId,
        _newId = newId ?? (() => const Uuid().v4()),
        _now = now ?? DateTime.now;

  final TablesRepository repository;
  final SyncQueueService queue;
  final Future<String> Function() _deviceId;
  final String Function() _newId;
  final DateTime Function() _now;

  Future<void> _enqueue(String id, String type, Map<String, dynamic> payload) async {
    await queue.enqueue(
      PendingOperation(id: id, entityType: type, deviceId: await _deviceId(), payload: payload, createdAt: _now()),
    );
  }

  /// Additions de la table en copie locale, en s'assurant que [order] (celle
  /// affichée à l'écran) y figure : elle vient du serveur ou de la copie.
  Future<List<OrderDetail>> _ordersOf(String tableId, OrderDetail order) async {
    final orders = await repository.cachedOrders(tableId);
    if (!orders.any((o) => o.id == order.id)) orders.add(order);
    return orders;
  }

  Future<OrderDetail> _replaceItems(
    String tableId,
    OrderDetail order,
    List<OrderDetail> orders,
    List<OrderItemDetail> items,
  ) async {
    final updated = order.copyWith(items: items, pendingSync: true);
    await repository.writeLocalOrders(tableId, [
      for (final o in orders)
        if (o.id == order.id) updated else o,
    ]);
    return updated;
  }

  /// Ouvre une addition sur la table (table libre ou réservée : « ouvrir » ;
  /// table déjà occupée : « nouvelle addition »). Le serveur décide à la
  /// synchronisation, sans jamais refuser une table devenue occupée entre-temps.
  Future<OrderDetail> openOrder(String tableId, {int? guestCount}) async {
    final id = _newId();
    await _enqueue(id, 'order_open', {'tableId': tableId, 'guestCount': ?guestCount});
    final order = OrderDetail(id: id, tableId: tableId, status: 'open', items: const [], pendingSync: true);
    final orders = [...await repository.cachedOrders(tableId), order];
    await repository.writeLocalOrders(tableId, orders, guestCount: guestCount);
    return order;
  }

  /// Ajoute une unité (ou le montant saisi) d'un produit : fusionne avec la
  /// ligne existante du même produit au même prix, comme le serveur, sinon crée
  /// une ligne. Lève [ArgumentError] si le produit ne peut pas être ajouté tel quel.
  Future<OrderDetail> addItem(
    String tableId,
    OrderDetail order,
    Product product, {
    double quantity = 1,
    double? unitPrice,
    double? amountPaid,
    bool sellAsUnit = false,
  }) async {
    final line = resolveLocalLine(
      product,
      quantity: quantity,
      unitPrice: unitPrice,
      amountPaid: amountPaid,
      sellAsUnit: sellAsUnit,
    );
    final orders = await _ordersOf(tableId, order);
    final current = orders.firstWhere((o) => o.id == order.id);

    final same = current.items
        .where((i) => i.productId == product.id && (i.unitPrice - line.unitPrice).abs() < 0.005)
        .firstOrNull;
    if (same != null) {
      final next = same.quantity + line.quantity;
      await _enqueue(_newId(), 'order_item_set', {
        'orderId': order.id,
        'itemId': same.id,
        'expectedQuantity': same.quantity,
        'quantity': next,
        'productName': product.name,
      });
      return _replaceItems(tableId, current, orders, [
        for (final i in current.items)
          if (i.id == same.id) _withQuantity(i, next) else i,
      ]);
    }

    final itemId = _newId();
    await _enqueue(_newId(), 'order_item_add', {
      'orderId': order.id,
      'itemId': itemId,
      'productId': product.id,
      'productName': product.name,
      'quantity': quantity,
      'unitPrice': ?unitPrice,
      'amountPaid': ?amountPaid,
      if (line.sellAsUnit) 'sellAsUnit': true,
    });
    return _replaceItems(tableId, current, orders, [
      ...current.items,
      OrderItemDetail(
        id: itemId,
        productId: product.id,
        productName: product.name,
        quantity: line.quantity,
        unitPrice: line.unitPrice,
        hasCasePricing: product.hasCasePricing,
        hasVariablePricing: product.hasVariablePricing,
        sellAsUnit: line.sellAsUnit,
        referenceSalePrice: product.referenceSalePrice,
      ),
    ]);
  }

  /// Fixe la quantité d'une ligne ; zéro ou moins la retire.
  Future<OrderDetail> setQuantity(String tableId, OrderDetail order, OrderItemDetail item, double quantity) async {
    if (quantity <= 0) return removeItem(tableId, order, item);
    final orders = await _ordersOf(tableId, order);
    final current = orders.firstWhere((o) => o.id == order.id);
    await _enqueue(_newId(), 'order_item_set', {
      'orderId': order.id,
      'itemId': item.id,
      'expectedQuantity': item.quantity,
      'quantity': quantity,
      'productName': item.productName,
    });
    return _replaceItems(tableId, current, orders, [
      for (final i in current.items)
        if (i.id == item.id) _withQuantity(i, quantity) else i,
    ]);
  }

  Future<OrderDetail> removeItem(String tableId, OrderDetail order, OrderItemDetail item) async {
    final orders = await _ordersOf(tableId, order);
    final current = orders.firstWhere((o) => o.id == order.id);
    await _enqueue(_newId(), 'order_item_remove', {
      'orderId': order.id,
      'itemId': item.id,
      'expectedQuantity': item.quantity,
      'productName': item.productName,
    });
    return _replaceItems(tableId, current, orders, [
      for (final i in current.items)
        if (i.id != item.id) i,
    ]);
  }

  static OrderItemDetail _withQuantity(OrderItemDetail item, double quantity) => OrderItemDetail(
        id: item.id,
        productId: item.productId,
        productName: item.productName,
        quantity: quantity,
        unitPrice: item.unitPrice,
        hasCasePricing: item.hasCasePricing,
        hasVariablePricing: item.hasVariablePricing,
        sellAsUnit: item.sellAsUnit,
        referenceSalePrice: item.referenceSalePrice,
      );
}
