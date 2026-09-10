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
    return getOpenOrderForTable(tableId);
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

  Future<OrderDetail> getOpenOrderForTable(String tableId) async {
    final json =
        await _api.get('$_base/tables/$tableId/order') as Map<String, dynamic>;
    return OrderDetail.fromJson(json);
  }

  Future<void> addItem(
    String orderId, {
    required String productId,
    required double quantity,
  }) {
    return _api.post(
      '$_base/orders/$orderId/items',
      body: {'productId': productId, 'quantity': quantity},
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
