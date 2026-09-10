import '../api/api_client.dart';
import 'tables_models.dart';

/// Correspond à apps/api/nestjs/src/tables/{tables,orders}.controller.ts.
class TablesRepository {
  TablesRepository(this._api, this.establishmentId);

  final ApiClient _api;
  final String establishmentId;

  String get _base => '/establishments/$establishmentId';

  Future<List<RestaurantTable>> listTables() async {
    final json = await _api.get('$_base/tables') as List<dynamic>;
    return json
        .map((e) => RestaurantTable.fromJson(e as Map<String, dynamic>))
        .toList();
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

  Future<OrderDetail> openTable(String tableId, {int? guestCount}) async {
    await _api.post(
      '$_base/tables/$tableId/open',
      body: {'guestCount': ?guestCount},
    );
    final orders = await listOpenOrdersForTable(tableId);
    return orders.first;
  }

  /// Ouvre une addition supplémentaire sur une table déjà occupée (bouton
  /// « Nouvelle addition ») — ne touche pas au statut de la table.
  Future<OrderDetail> openAdditionalOrder(String tableId, {int? guestCount}) async {
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
    return json
        .map((e) => OrderDetail.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addItem(
    String orderId, {
    required String productId,
    required double quantity,
    double? unitPrice,
  }) {
    return _api.post(
      '$_base/orders/$orderId/items',
      body: {
        'productId': productId,
        'quantity': quantity,
        'unitPrice': ?unitPrice,
      },
    );
  }

  Future<void> updateItemQuantity(String orderId, String itemId, double quantity) {
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
