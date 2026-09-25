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

  /// [period] est ignoré si [from]/[to] sont fournis — même convention que
  /// [getSummary] (utilisé par `HomeDashboard` pour filtrer sur un jour
  /// précis choisi par l'utilisateur, décision du 2026-09-14).
  Future<PaymentCategoryBreakdown> getPaymentCategoryBreakdown({
    String? period,
    String? from,
    String? to,
  }) async {
    final json = await _api.get(
      '$_base/payment-category-breakdown',
      query: {
        if (from == null && to == null) 'period': period ?? 'day',
        'from': ?from,
        'to': ?to,
      },
    ) as Map<String, dynamic>;
    return PaymentCategoryBreakdown.fromJson(json);
  }

  /// [dates] : un ou plusieurs jours au format `YYYY-MM-DD` (sélection
  /// multiple — demande utilisateur du 2026-09-25), joints par des virgules
  /// pour le serveur. Export au format PDF (plus Excel, même décision).
  Future<({List<int> bytes, String? filename})> exportBeveragesSoldPdf(
    List<String> dates,
  ) {
    return _api.getBytes('$_base/beverages-sold.pdf', query: {'dates': dates.join(',')});
  }

  /// Même principe qu'[exportBeveragesSoldPdf], pour les catégories à prix
  /// variable (Poulets/Poissons/Plats africains).
  Future<({List<int> bytes, String? filename})> exportPlatsSoldPdf(
    List<String> dates,
  ) {
    return _api.getBytes('$_base/plats-sold.pdf', query: {'dates': dates.join(',')});
  }
}
