import '../api/api_client.dart';
import 'pos_models.dart';

/// Correspond à apps/api/nestjs/src/pos/sales.controller.ts.
class PosRepository {
  PosRepository(this._api, this.establishmentId);

  final ApiClient _api;
  final String establishmentId;

  Future<SaleResult> createSale({
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> payments,
    Map<String, dynamic>? discount,
    String? customerId,
    String? orderId,
    String? tableId,
    String? source,
  }) async {
    final json = await _api.post('/establishments/$establishmentId/sales', body: {
      'items': items,
      'payments': payments,
      'discount': ?discount,
      'customerId': ?customerId,
      'orderId': ?orderId,
      'tableId': ?tableId,
      'source': ?source,
    }) as Map<String, dynamic>;
    return SaleResult.fromJson(json);
  }

  Future<SaleResult> refund(String saleId) async {
    final json = await _api.post('/establishments/$establishmentId/sales/$saleId/refund') as Map<String, dynamic>;
    return SaleResult.fromJson(json);
  }

  Future<List<SaleResult>> listForDay(String day) async {
    final json = await _api.get('/establishments/$establishmentId/sales', query: {'day': day}) as List<dynamic>;
    return json.map((e) => SaleResult.fromJson(e as Map<String, dynamic>)).toList();
  }
}
