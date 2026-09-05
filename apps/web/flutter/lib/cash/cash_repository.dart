import '../api/api_client.dart';
import 'cash_models.dart';

/// Correspond à apps/api/nestjs/src/cash/cash.controller.ts.
class CashRepository {
  CashRepository(this._api, this.establishmentId);

  final ApiClient _api;
  final String establishmentId;

  String get _base => '/establishments/$establishmentId/cash/closings';

  Future<List<CashClosing>> listClosings() async {
    final json = await _api.get(_base) as List<dynamic>;
    return json.map((e) => CashClosing.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<CashClosing> close({required DateTime openedAt, required double countedAmount}) async {
    final json = await _api.post(_base, body: {
      'openedAt': openedAt.toUtc().toIso8601String(),
      'countedAmount': countedAmount,
    }) as Map<String, dynamic>;
    return CashClosing.fromJson(json);
  }
}
