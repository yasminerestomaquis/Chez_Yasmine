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
    final json = await _api.post(
      '/establishments/$establishmentId/sales',
      body: {
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
      },
    ) as Map<String, dynamic>;
    return SaleResult.fromJson(json);
  }

  /// Suggestion éditable pour la caisse — jamais imposée côté serveur.
  Future<int?> lastOrderNumber() async {
    final json = await _api.get(
      '/establishments/$establishmentId/sales/last-order-number',
    ) as Map<String, dynamic>;
    return json['orderNumber'] as int?;
  }

  /// Suggestion éditable pour la caisse — jamais imposée côté serveur.
  Future<int?> lastMarketNumber() async {
    final json = await _api.get(
      '/establishments/$establishmentId/sales/last-market-number',
    ) as Map<String, dynamic>;
    return json['marketNumber'] as int?;
  }

  Future<SaleResult> refund(String saleId) async {
    final json = await _api.post(
      '/establishments/$establishmentId/sales/$saleId/refund',
    ) as Map<String, dynamic>;
    return SaleResult.fromJson(json);
  }

  Future<List<SaleResult>> listForDay(String day) async {
    final json = await _api.get(
      '/establishments/$establishmentId/sales',
      query: {'day': day},
    ) as List<dynamic>;
    return json
        .map((e) => SaleResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Même route que [listForDay], bornes explicites (date + heure + minute) —
  /// utilisé par Rapports > Boissons/Plats vendus pour un intervalle précis
  /// plutôt qu'un jour calendaire entier (décision utilisateur du 2026-09-26).
  Future<List<SaleResult>> listForRange(DateTime from, DateTime to) async {
    final json = await _api.get(
      '/establishments/$establishmentId/sales',
      query: {'from': from.toUtc().toIso8601String(), 'to': to.toUtc().toIso8601String()},
    ) as List<dynamic>;
    return json
        .map((e) => SaleResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Corrige le nombre de produits vendus d'une ligne — voir docs/api/pos.md
  /// (« Correction d'une vente déjà enregistrée »). Le stock est réajusté
  /// par la différence côté serveur, jamais une valeur absolue. Ne s'applique
  /// jamais à une ligne à prix de référence variable (ex. Gbêlê) — voir
  /// [correctReferencePricedItemAmount].
  Future<SaleResult> updateItemQuantity(
    String saleId,
    String itemId,
    double quantity,
  ) async {
    final json = await _api.patch(
      '/establishments/$establishmentId/sales/$saleId/items/$itemId',
      body: {'quantity': quantity},
    ) as Map<String, dynamic>;
    return SaleResult.fromJson(json);
  }

  /// Corrige une ligne à prix de référence variable (ex. Gbêlê) via le
  /// MONTANT payé — le serveur recalcule quantité ET prix unitaire ensemble
  /// (`resolveReferencePriceLine`), jamais via [updateItemQuantity] qui
  /// multiplierait une quantité arbitraire par l'ancien prix unitaire figé
  /// (décision utilisateur du 2026-09-26, voir docs/api/pos.md).
  Future<SaleResult> correctReferencePricedItemAmount(
    String saleId,
    String itemId,
    double amountPaid,
  ) async {
    final json = await _api.patch(
      '/establishments/$establishmentId/sales/$saleId/items/$itemId/amount',
      body: {'amountPaid': amountPaid},
    ) as Map<String, dynamic>;
    return SaleResult.fromJson(json);
  }

  /// Corrige le mode de paiement (Espèces/Mobile Money) d'une ligne déjà
  /// enregistrée — le montant ne change jamais ici.
  Future<SaleResult> updatePaymentMethod(
    String saleId,
    String paymentId,
    String method,
  ) async {
    final json = await _api.patch(
      '/establishments/$establishmentId/sales/$saleId/payments/$paymentId',
      body: {'method': method},
    ) as Map<String, dynamic>;
    return SaleResult.fromJson(json);
  }
}
