import '../api/api_client.dart';
import 'report_models.dart';

/// Correspond à apps/api/nestjs/src/reports/reports.controller.ts.
class ReportsRepository {
  ReportsRepository(this._api, this.establishmentId);

  final ApiClient _api;
  final String establishmentId;

  String get _base => '/establishments/$establishmentId/reports';

  /// [period] est ignoré si [from]/[to] sont fournis (même priorité que
  /// côté serveur, voir `ReportsService.resolveRange`) — utilisé par
  /// `ReportsPage` pour recalculer la période de comparaison précédente
  /// (même borne `from`/`to` déjà exposée par l'API, pas de nouvelle route).
  Future<ReportSummary> getSummary({
    String? period,
    String? from,
    String? to,
  }) async {
    final json = await _api.get(
      '$_base/summary',
      query: {
        if (from == null && to == null) 'period': period ?? 'day',
        'from': ?from,
        'to': ?to,
      },
    ) as Map<String, dynamic>;
    return ReportSummary.fromJson(json);
  }

  Future<String> exportSummaryCsv({String period = 'day'}) {
    return _api.getText('$_base/summary.csv', query: {'period': period});
  }

  Future<PaymentCategoryBreakdown> getPaymentCategoryBreakdown({
    String period = 'day',
  }) async {
    final json = await _api.get(
      '$_base/payment-category-breakdown',
      query: {'period': period},
    ) as Map<String, dynamic>;
    return PaymentCategoryBreakdown.fromJson(json);
  }

  /// [date] au format `YYYY-MM-DD` (jour choisi par l'utilisateur).
  Future<({List<int> bytes, String? filename})> exportBeveragesSoldExcel(
    String date,
  ) {
    return _api.getBytes('$_base/beverages-sold.xlsx', query: {'date': date});
  }
}
