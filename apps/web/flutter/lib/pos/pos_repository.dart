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
    String? id,
    int? orderNumber,
    int? marketNumber,
  }) async {
    final json = await _api.post('/establishments/$establishmentId/sales', body: {
      'id': ?id,
      'items': items,
      'payments': payments,
      'discount': ?discount,
      'customerId': ?customerId,
      'orderId': ?orderId,
      'tableId': ?tableId,
      'source': ?source,
      'orderNumber': ?orderNumber,
      'marketNumber': ?marketNumber,
    }) as Map<String, dynamic>;
    return SaleResult.fromJson(json);
  }

  /// Suggestion éditable pour la caisse — jamais imposée côté serveur.
  Future<int?> lastOrderNumber() async {
    final json = await _api.get('/establishments/$establishmentId/sales/last-order-number') as Map<String, dynamic>;
    return json['orderNumber'] as int?;
  }

  /// Suggestion éditable pour la caisse — jamais imposée côté serveur.
  Future<int?> lastMarketNumber() async {
    final json = await _api.get('/establishments/$establishmentId/sales/last-market-number') as Map<String, dynamic>;
    return json['marketNumber'] as int?;
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
