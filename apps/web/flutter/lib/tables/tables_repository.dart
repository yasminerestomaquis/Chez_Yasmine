import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../common/read_cache.dart';
import '../sync/connectivity_status.dart';
import '../sync/sync_queue_service.dart';
import 'tables_models.dart';

/// Correspond à apps/api/nestjs/src/tables/{tables,orders}.controller.ts.
class TablesRepository {
  TablesRepository(
    this._api,
    this.establishmentId, {
    ReadCache? cache,
    SyncQueueService? syncQueue,
    Future<bool> Function()? isOnline,
  })  : _cache = cache ?? ReadCache(establishmentId),
        _syncQueue = syncQueue ?? SyncQueueService(_api, establishmentId),
        _isOnline = isOnline ?? _defaultIsOnline;

  final ApiClient _api;
  final String establishmentId;
  final ReadCache _cache;
  final SyncQueueService _syncQueue;
  final Future<bool> Function() _isOnline;

  /// Délai maximal et valeur par défaut « en ligne » : si l'état de la
  /// connexion ne peut pas être lu (plugin absent, plateforme sans support), on
  /// tente quand même la synchronisation plutôt que de rester bloqué dessus.
  static Future<bool> _defaultIsOnline() async {
    try {
      return await ConnectivityStatus.isOnline().timeout(const Duration(seconds: 2), onTimeout: () => true);
    } catch (_) {
      return true;
    }
  }

  String get _base => '/establishments/$establishmentId';

  Future<List<RestaurantTable>> listTables() async {
    final json = await _api.get('$_base/tables') as List<dynamic>;
    return json
        .map((e) => RestaurantTable.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static const _tablesCacheName = 'tables';
  String _ordersCacheName(String tableId) => 'orders_$tableId';

  /// Plan de salle, avec repli sur la dernière copie locale quand le serveur
  /// est injoignable (consultation hors ligne, voir docs/api/sync.md).
  Future<Cached<List<RestaurantTable>>> loadTables() {
    return _readReflectingPending(
      name: _tablesCacheName,
      fetch: () async => await _api.get('$_base/tables') as Object,
      parse: (json) => (json as List<dynamic>)
          .map((e) => RestaurantTable.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Avant de lire le serveur, envoie ce que l'appareil a saisi hors ligne
  /// (ouvertures de table, articles, encaissements d'addition) : sans cela, la
  /// lecture ne le contiendrait pas et l'écran montrerait un état en retard
  /// sur ce que l'utilisateur vient de faire. Silencieux si l'appareil est
  /// hors ligne ou si l'envoi échoue : les opérations restent en file.
  Future<void> _syncPendingOperations() async {
    try {
      if (!await _syncQueue.hasPendingTableOperations()) return;
      if (!await _isOnline()) return;
      await _syncQueue.syncAll().timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  /// Lecture « avec repli », mais qui ne remplace JAMAIS la copie locale par
  /// l'état du serveur tant que des opérations de tables restent en file : le
  /// serveur ne les connaît pas encore, les voir disparaître de l'écran
  /// pousserait à les saisir une seconde fois (doublons à la synchronisation).
  Future<Cached<T>> _readReflectingPending<T>({
    required String name,
    required Future<Object> Function() fetch,
    required T Function(Object json) parse,
  }) async {
    await _syncPendingOperations();
    if (await _syncQueue.hasPendingTableOperations()) {
      final local = await _cache.load(name);
      if (local != null && local.json != null) {
        return Cached(parse(local.json!), cachedAt: local.savedAt);
      }
    }
    return _cache.read(name: name, fetch: fetch, parse: parse);
  }

  Future<void> createTable(String name, {String? zone}) {
    return _api.post('$_base/tables', body: {'name': name, 'zone': ?zone});
  }

  Future<void> updateTable(String tableId, {String? name, String? zone}) {
    return _api.patch(
      '$_base/tables/$tableId',
      body: {'name': ?name, 'zone': ?zone},
    );
  }

  Future<void> deleteTable(String tableId) {
    return _api.delete('$_base/tables/$tableId');
  }

  /// Ouvre la table sur le serveur. La lecture qui suit ne sert qu'à
  /// préchauffer la copie locale : son échec n'annule PAS l'ouverture (déjà
  /// faite côté serveur) et ne doit pas faire croire qu'elle a échoué — l'écran
  /// rouvrirait alors la table sur l'appareil et créerait une addition en double.
  Future<void> openTable(String tableId, {int? guestCount}) async {
    await _api.post(
      '$_base/tables/$tableId/open',
      body: {'guestCount': ?guestCount},
    );
    try {
      await listOpenOrdersForTable(tableId);
    } catch (_) {}
  }

  /// Ouvre une addition supplémentaire sur une table déjà occupée (bouton
  /// « Nouvelle addition ») — ne touche pas au statut de la table.
  Future<OrderDetail> openAdditionalOrder(
    String tableId, {
    int? guestCount,
  }) async {
    final json = await _api.post(
      '$_base/tables/$tableId/additions',
      body: {'guestCount': ?guestCount},
    ) as Map<String, dynamic>;
    return OrderDetail.fromJson(json);
  }

  /// Libère la table sans condition : annule toutes ses additions ouvertes,
  /// aucune confirmation. Voir docs/api/tables.md.
  Future<void> releaseTable(String tableId) {
    return _api.post('$_base/tables/$tableId/release');
  }

  Future<void> createReservation(
    String tableId, {
    String? customerName,
    String? phone,
    required DateTime reservedAt,
  }) {
    return _api.post(
      '$_base/tables/$tableId/reservations',
      body: {
        'customerName': ?customerName,
        'phone': ?phone,
        'reservedAt': reservedAt.toUtc().toIso8601String(),
      },
    );
  }

  Future<void> cancelReservation(String reservationId) {
    return _api.post('$_base/reservations/$reservationId/cancel');
  }

  /// Toutes les additions ouvertes de la table (une table peut en avoir
  /// plusieurs simultanément — voir docs/api/tables.md).
  Future<List<OrderDetail>> listOpenOrdersForTable(String tableId) async {
    final json =
        await _api.get('$_base/tables/$tableId/orders') as List<dynamic>;
    try {
      // Pas d'écrasement de la copie locale tant que des saisies hors ligne
      // attendent leur synchronisation (voir `_readReflectingPending`).
      if (!await _syncQueue.hasPendingTableOperations()) {
        await _cache.save(_ordersCacheName(tableId), json);
      }
    } catch (_) {
      // Stockage indisponible : la lecture en ligne reste valable.
    }
    return json
        .map((e) => OrderDetail.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Comme [listOpenOrdersForTable], avec repli sur la dernière copie locale
  /// de cette table quand le serveur est injoignable.
  Future<Cached<List<OrderDetail>>> loadOpenOrders(String tableId) {
    return _readReflectingPending(
      name: _ordersCacheName(tableId),
      fetch: () async => await _api.get('$_base/tables/$tableId/orders') as Object,
      parse: (json) => (json as List<dynamic>)
          .map((e) => OrderDetail.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static final Map<String, DateTime> _lastPrefetch = {};

  @visibleForTesting
  static void resetPrefetchThrottle() => _lastPrefetch.clear();

  /// Télécharge en arrière-plan les additions ouvertes de toutes les tables
  /// occupées, pour qu'elles soient consultables (et encaissables) hors ligne
  /// même sans avoir été ouvertes à l'écran. 3 requêtes en parallèle, arrêt à la
  /// première coupure, au plus une fois par minute et par établissement.
  Future<void> prefetchOpenOrders(List<RestaurantTable> tables) async {
    if (await _syncQueue.hasPendingTableOperations()) return;
    final now = DateTime.now();
    final last = _lastPrefetch[establishmentId];
    if (last != null && now.difference(last) < const Duration(seconds: 60)) return;
    _lastPrefetch[establishmentId] = now;

    final targets = tables.where((t) => t.openOrderCount > 0).toList();
    var next = 0;
    var unreachable = false;
    Future<void> worker() async {
      while (!unreachable && next < targets.length) {
        final table = targets[next++];
        try {
          await listOpenOrdersForTable(table.id);
        } catch (error) {
          if (isNetworkFailure(error)) unreachable = true;
        }
      }
    }

    await Future.wait(List.generate(3, (_) => worker()));
  }

  /// Après un encaissement enregistré hors ligne : retire l'addition de la
  /// copie locale des additions ouvertes et met à jour la table (nombre
  /// d'additions, total, libre s'il n'en reste aucune) — sans quoi l'écran
  /// proposerait d'encaisser une seconde fois la même addition. La date de la
  /// copie n'est pas rafraîchie : elle reste celle du dernier vrai chargement.
  Future<void> markOrderCheckedOutLocally(String tableId, OrderDetail order) async {
    final orders = await _cache.load(_ordersCacheName(tableId));
    if (orders != null && orders.json is List) {
      final remaining = (orders.json as List).where((o) => (o as Map)['id'] != order.id).toList();
      await _cache.save(_ordersCacheName(tableId), remaining, savedAt: orders.savedAt);
    }
    final tables = await _cache.load(_tablesCacheName);
    if (tables != null && tables.json is List) {
      final updated = [
        for (final raw in tables.json as List)
          if ((raw as Map)['id'] == tableId) _tableAfterCheckout(Map<String, dynamic>.from(raw), order.total) else raw,
      ];
      await _cache.save(_tablesCacheName, updated, savedAt: tables.savedAt);
    }
  }

  /// Copie locale des additions ouvertes d'une table (liste vide sans copie).
  Future<List<OrderDetail>> cachedOrders(String tableId) async {
    final cached = await _cache.load(_ordersCacheName(tableId));
    if (cached == null || cached.json is! List) return [];
    return [
      for (final raw in cached.json as List) OrderDetail.fromJson(Map<String, dynamic>.from(raw as Map)),
    ];
  }

  /// Écrit la copie locale des additions d'une table après une saisie hors
  /// ligne, et met la table à jour (statut, nombre d'additions, total). La date
  /// de la copie reste celle du dernier vrai chargement (nouvelle copie : la
  /// date du jour). [guestCount] : convives saisis à l'ouverture.
  Future<void> writeLocalOrders(String tableId, List<OrderDetail> orders, {int? guestCount}) async {
    final existing = await _cache.load(_ordersCacheName(tableId));
    await _cache.save(
      _ordersCacheName(tableId),
      orders.map((o) => o.toJson()).toList(),
      savedAt: existing?.savedAt,
    );
    final tables = await _cache.load(_tablesCacheName);
    if (tables != null && tables.json is List) {
      final updated = [
        for (final raw in tables.json as List)
          if ((raw as Map)['id'] == tableId)
            _tableWithOrders(Map<String, dynamic>.from(raw), orders, guestCount)
          else
            raw,
      ];
      await _cache.save(_tablesCacheName, updated, savedAt: tables.savedAt);
    }
  }

  static Map<String, dynamic> _tableWithOrders(Map<String, dynamic> table, List<OrderDetail> orders, int? guestCount) {
    if (orders.isEmpty) {
      return {...table, 'openOrderCount': 0, 'currentTotal': null, 'guestCount': null, 'status': 'free'};
    }
    final status = table['status'] == 'free' || table['status'] == 'reserved' ? 'occupied' : table['status'];
    return {
      ...table,
      'status': status,
      'openOrderCount': orders.length,
      'currentTotal': orders.fold<double>(0, (sum, o) => sum + o.total),
      'guestCount': guestCount ?? table['guestCount'],
    };
  }

  static Map<String, dynamic> _tableAfterCheckout(Map<String, dynamic> table, double orderTotal) {
    final count = ((table['openOrderCount'] as num?)?.toInt() ?? 1) - 1;
    if (count <= 0) {
      return {...table, 'openOrderCount': 0, 'currentTotal': null, 'guestCount': null, 'status': 'free'};
    }
    final total = ((table['currentTotal'] as num?)?.toDouble() ?? orderTotal) - orderTotal;
    return {...table, 'openOrderCount': count, 'currentTotal': total < 0 ? 0 : total};
  }


  Future<void> addItem(
    String orderId, {
    required String productId,
    required double quantity,
    double? unitPrice,
    double? amountPaid,
    bool sellAsUnit = false,
  }) {
    return _api.post(
      '$_base/orders/$orderId/items',
      body: {
        'productId': productId,
        'quantity': quantity,
        'unitPrice': ?unitPrice,
        'amountPaid': ?amountPaid,
        if (sellAsUnit) 'sellAsUnit': true,
      },
    );
  }

  Future<void> updateItemQuantity(
    String orderId,
    String itemId,
    double quantity,
  ) {
    return _api.patch(
      '$_base/orders/$orderId/items/$itemId',
      body: {'quantity': quantity},
    );
  }

  Future<void> removeItem(String orderId, String itemId) {
    return _api.delete('$_base/orders/$orderId/items/$itemId');
  }

  Future<void> transfer(String orderId, String toTableId) {
    return _api.post(
      '$_base/orders/$orderId/transfer',
      body: {'toTableId': toTableId},
    );
  }
}
