import '../api/api_client.dart';
import 'payroll_models.dart';

/// Correspond à apps/api/nestjs/src/payroll/payroll.controller.ts.
class PayrollRepository {
  PayrollRepository(this._api, this.establishmentId);

  final ApiClient _api;
  final String establishmentId;

  String get _base => '/establishments/$establishmentId/payroll';

  Future<PayrollDashboard> getDashboard({
    required int year,
    required int month,
  }) async {
    final json = await _api.get(
      '$_base/dashboard',
      query: {'year': '$year', 'month': '$month'},
    ) as Map<String, dynamic>;
    return PayrollDashboard.fromJson(json);
  }

  Future<List<PayrollRun>> listRuns() async {
    final json = await _api.get('$_base/runs') as List<dynamic>;
    return json
        .map((e) => PayrollRun.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<PayrollRun> prepare({
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final json = await _api.post(
      '$_base/runs',
      body: {
        'periodStart': _dateOnly(periodStart),
        'periodEnd': _dateOnly(periodEnd),
      },
    ) as Map<String, dynamic>;
    return PayrollRun.fromJson(json);
  }

  Future<void> updateLine(
    String runId,
    String lineId, {
    required double advance,
    required double adjustment,
  }) {
    return _api.patch(
      '$_base/runs/$runId/lines/$lineId',
      body: {'advance': advance, 'adjustment': adjustment},
    );
  }

  Future<void> validate(String runId) =>
      _api.post('$_base/runs/$runId/validate');

  Future<void> pay(String runId) => _api.post('$_base/runs/$runId/pay');

  Future<void> cancel(String runId) => _api.post('$_base/runs/$runId/cancel');
}
