import '../api/api_client.dart';
import '../common/order_number_field.dart';
import 'stock_models.dart';

/// Correspond à apps/api/nestjs/src/stock/stock.controller.ts.
class StockRepository {
  StockRepository(this._api, this.establishmentId);

  final ApiClient _api;
  final String establishmentId;

  Future<List<StockAlert>> listAlerts() async {
    final json = await _api.get(
      '/establishments/$establishmentId/stock/alerts',
    ) as List<dynamic>;
    return json
        .map((e) => StockAlert.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<StockMovementTotals>> listMovementTotals() async {
    final json = await _api.get(
      '/establishments/$establishmentId/stock/movement-totals',
    ) as List<dynamic>;
    return json
        .map((e) => StockMovementTotals.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<StockMovement>> listMovements(String productId) async {
    final json = await _api.get(
      '/establishments/$establishmentId/products/$productId/stock-movements',
    ) as List<dynamic>;
    return json
        .map((e) => StockMovement.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createMovement(
    String productId, {
    required String type,
    required double quantity,
    String? reason,
    String? id,
    int? marketNumber,
    int? orderNumber,
  }) {
    return _api.post(
      '/establishments/$establishmentId/products/$productId/stock-movements',
      body: {
        'id': ?id,
        'type': type,
        'quantity': quantity,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        'marketNumber': ?marketNumber,
        'orderNumber': ?orderNumber,
      },
    );
  }

  /// N° de commande proposés (et défaut) pour un produit.
  Future<OrderNumberChoices> orderNumbers(String productId) async {
    final json = await _api.get('/establishments/$establishmentId/products/$productId/order-numbers') as Map<String, dynamic>;
    return OrderNumberChoices.fromJson(json);
  }

  /// Codes `stock.*` à bascule client accordés à l'utilisateur courant (pour
  /// l'instant, seulement `stock.view_value` — voir `StockController.myPermissions`).
  Future<Set<String>> getMyPermissions() async {
    final json = await _api.get('/establishments/$establishmentId/stock/permissions') as Map<String, dynamic>;
    return (json['permissions'] as List<dynamic>).cast<String>().toSet();
  }
}
