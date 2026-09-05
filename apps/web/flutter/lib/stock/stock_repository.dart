import '../api/api_client.dart';
import 'stock_models.dart';

/// Correspond à apps/api/nestjs/src/stock/stock.controller.ts.
class StockRepository {
  StockRepository(this._api, this.establishmentId);

  final ApiClient _api;
  final String establishmentId;

  Future<List<StockAlert>> listAlerts() async {
    final json = await _api.get('/establishments/$establishmentId/stock/alerts') as List<dynamic>;
    return json.map((e) => StockAlert.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<StockMovement>> listMovements(String productId) async {
    final json = await _api.get('/establishments/$establishmentId/products/$productId/stock-movements') as List<dynamic>;
    return json.map((e) => StockMovement.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> createMovement(String productId, {required String type, required double quantity, String? reason}) {
    return _api.post(
      '/establishments/$establishmentId/products/$productId/stock-movements',
      body: {'type': type, 'quantity': quantity, if (reason != null && reason.isNotEmpty) 'reason': reason},
    );
  }
}
