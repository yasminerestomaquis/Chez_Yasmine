import '../api/api_client.dart';
import '../common/order_number_field.dart';
import 'loss_models.dart';

/// Correspond à apps/api/nestjs/src/losses/losses.controller.ts.
class LossesRepository {
  LossesRepository(this._api, this.establishmentId);

  final ApiClient _api;
  final String establishmentId;

  String get _base => '/establishments/$establishmentId/losses';

  Future<List<Loss>> listLosses() async {
    final json = await _api.get(_base) as List<dynamic>;
    return json.map((e) => Loss.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// `id` généré par l'appelant (plutôt qu'ici) pour qu'il puisse être réutilisé
  /// comme clé d'idempotence de la file hors ligne si la requête échoue par
  /// coupure réseau — voir `record_loss_dialog.dart`.
  /// N° de commande proposés (et défaut) pour un produit.
  Future<OrderNumberChoices> orderNumbers(String productId) async {
    final json = await _api.get('$_base/order-numbers/$productId') as Map<String, dynamic>;
    return OrderNumberChoices.fromJson(json);
  }

  Future<void> recordLoss({
    required String id,
    required String productId,
    required double quantity,
    String? reason,
    DateTime? createdAt,
    bool sellAsUnit = false,
    int? orderNumber,
  }) {
    return _api.post(_base, body: {
      'id': id,
      'productId': productId,
      'quantity': quantity,
      'reason': ?reason,
      'createdAt': ?createdAt?.toUtc().toIso8601String(),
      if (sellAsUnit) 'sellAsUnit': true,
      'orderNumber': ?orderNumber,
    });
  }

  /// Correction d'une perte (permission `losses.edit`) : date, produit,
  /// quantité, motif. Le serveur recalcule le stock en conséquence.
  Future<void> updateLoss(
    String lossId, {
    required String productId,
    required double quantity,
    required String reason,
    required DateTime createdAt,
    bool sellAsUnit = false,
    int? orderNumber,
  }) {
    return _api.patch('$_base/$lossId', body: {
      'productId': productId,
      'quantity': quantity,
      'reason': reason,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'sellAsUnit': sellAsUnit,
      'orderNumber': ?orderNumber,
    });
  }

  /// Supprime une perte et restitue sa quantité au stock (permission `losses.edit`).
  Future<void> deleteLoss(String lossId) => _api.delete('$_base/$lossId');
}
