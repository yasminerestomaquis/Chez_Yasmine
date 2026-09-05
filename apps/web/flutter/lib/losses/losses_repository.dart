import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
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

  Future<void> recordLoss({required String productId, required double quantity, String? reason}) {
    return _api.post(_base, body: {
      'id': const Uuid().v4(),
      'productId': productId,
      'quantity': quantity,
      'reason': ?reason,
    });
  }
}
