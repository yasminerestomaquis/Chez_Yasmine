import '../api/api_client.dart';
import 'report_models.dart';

/// Correspond à apps/api/nestjs/src/reports/reports.controller.ts.
class ReportsRepository {
  ReportsRepository(this._api, this.establishmentId);

  final ApiClient _api;
  final String establishmentId;

  String get _base => '/establishments/$establishmentId/reports';

  Future<ReportSummary> getSummary({String period = 'day'}) async {
    final json = await _api.get('$_base/summary', query: {'period': period}) as Map<String, dynamic>;
    return ReportSummary.fromJson(json);
  }

  Future<String> exportSummaryCsv({String period = 'day'}) {
    return _api.getText('$_base/summary.csv', query: {'period': period});
  }
}
