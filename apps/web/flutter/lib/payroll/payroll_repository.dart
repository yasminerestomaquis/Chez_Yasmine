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

  /// [from] / [to] (inclus, optionnels) : ne garde que les paies dont la
  /// période chevauche cet intervalle — historique des paies sur une période
  /// choisie par l'utilisateur.
  Future<List<PayrollRun>> listRuns({DateTime? from, DateTime? to}) async {
    final query = {
      if (from != null) 'from': _dateOnly(from),
      if (to != null) 'to': _dateOnly(to),
    };
    final json = await _api.get(
      '$_base/runs',
      query: query.isEmpty ? null : query,
    ) as List<dynamic>;
    return json
        .map((e) => PayrollRun.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  /// Ajoute un employé actif sur la paie (salaire hebdomadaire courant, sans
  /// avance ni ajustement). Exige le serveur.
  Future<void> addLine(String runId, String employeeId) =>
      _api.post('$_base/runs/$runId/lines', body: {'employeeId': employeeId});

  /// Retire un employé de la paie ; pour une paie payée, la dépense « Salaires »
  /// liée est ajustée côté serveur.
  Future<void> removeLine(String runId, String lineId) =>
      _api.delete('$_base/runs/$runId/lines/$lineId');

  /// [periodType] : 'weekly' (employés payés à la semaine) ou 'monthly'
  /// (employés payés au mois).
  Future<PayrollRun> prepare({
    required DateTime periodStart,
    required DateTime periodEnd,
    String periodType = 'weekly',
  }) async {
    final json = await _api.post(
      '$_base/runs',
      body: {
        'periodStart': _dateOnly(periodStart),
        'periodEnd': _dateOnly(periodEnd),
        'periodType': periodType,
      },
    ) as Map<String, dynamic>;
    return PayrollRun.fromJson(json);
  }

  /// Corrige la période d'une paie non annulée — pour une paie déjà payée, la
  /// date de la dépense « Salaires » liée suit la fin de période (serveur).
  Future<void> updateRun(
    String runId, {
    required DateTime periodStart,
    required DateTime periodEnd,
  }) {
    return _api.patch(
      '$_base/runs/$runId',
      body: {
        'periodStart': _dateOnly(periodStart),
        'periodEnd': _dateOnly(periodEnd),
      },
    );
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
