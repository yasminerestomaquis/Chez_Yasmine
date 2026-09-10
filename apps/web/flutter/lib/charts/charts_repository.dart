import '../api/api_client.dart';
import 'chart_models.dart';

/// Correspond à apps/api/nestjs/src/charts/charts.controller.ts.
class ChartsRepository {
  ChartsRepository(this._api, this.establishmentId);

  final ApiClient _api;
  final String establishmentId;

  String get _base => '/establishments/$establishmentId/charts';

  Map<String, String> _query(Map<String, String?> params) {
    final query = <String, String>{};
    for (final entry in params.entries) {
      final value = entry.value;
      if (value != null) query[entry.key] = value;
    }
    return query;
  }

  Future<WeeklyChart> getWeekly({
    required String metric,
    String? weekStart,
  }) async {
    final json = await _api.get(
      '$_base/weekly',
      query: _query({'metric': metric, 'weekStart': weekStart}),
    ) as Map<String, dynamic>;
    return WeeklyChart.fromJson(json);
  }

  /// [categoryIds] vide/nul : une série par catégorie (comportement par
  /// défaut). Une ou plusieurs catégories fournies : une seule série,
  /// somme jour par jour de ces catégories — sélection multiple.
  Future<WeeklyChart> getWeeklyByCategory({
    required String metric,
    String? weekStart,
    Set<String>? categoryIds,
  }) async {
    final json = await _api.get(
      '$_base/weekly-by-category',
      query: _query({
        'metric': metric,
        'weekStart': weekStart,
        'categoryIds': (categoryIds == null || categoryIds.isEmpty)
            ? null
            : categoryIds.join(','),
      }),
    ) as Map<String, dynamic>;
    return WeeklyChart.fromJson(json);
  }

  Future<WeeklyChart> getWeeklyByProduct({
    required String metric,
    String? weekStart,
    String? productId,
  }) async {
    final json = await _api.get(
      '$_base/weekly-by-product',
      query: _query({
        'metric': metric,
        'weekStart': weekStart,
        'productId': productId,
      }),
    ) as Map<String, dynamic>;
    return WeeklyChart.fromJson(json);
  }

  Future<MonthlyChart> getMonthly({
    required String metric,
    required int year,
  }) async {
    final json = await _api.get(
      '$_base/monthly',
      query: _query({'metric': metric, 'year': '$year'}),
    ) as Map<String, dynamic>;
    return MonthlyChart.fromJson(json);
  }

  Future<RankingChart> getTop({
    required String metric,
    String? from,
    String? to,
  }) async {
    final json = await _api.get(
      '$_base/top',
      query: _query({'metric': metric, 'from': from, 'to': to}),
    ) as Map<String, dynamic>;
    return RankingChart.fromJson(json);
  }

  Future<StockLotsChart> getStockLots({required String productId}) async {
    final json = await _api.get(
      '$_base/stock-lots',
      query: _query({'productId': productId}),
    ) as Map<String, dynamic>;
    return StockLotsChart.fromJson(json);
  }

  Future<WeeklyChart> getExpensesWeekly({String? weekStart}) async {
    final json = await _api.get(
      '$_base/expenses/weekly',
      query: _query({'weekStart': weekStart}),
    ) as Map<String, dynamic>;
    return WeeklyChart.fromJson(json);
  }

  Future<WeeklyChart> getExpensesWeeklyByCategory({
    String? weekStart,
    String? category,
  }) async {
    final json = await _api.get(
      '$_base/expenses/weekly-by-category',
      query: _query({'weekStart': weekStart, 'category': category}),
    ) as Map<String, dynamic>;
    return WeeklyChart.fromJson(json);
  }

  Future<MonthlyChart> getExpensesMonthly({required int year}) async {
    final json = await _api.get(
      '$_base/expenses/monthly',
      query: _query({'year': '$year'}),
    ) as Map<String, dynamic>;
    return MonthlyChart.fromJson(json);
  }

  Future<RankingChart> getExpensesTop({String? from, String? to}) async {
    final json = await _api.get(
      '$_base/expenses/top',
      query: _query({'from': from, 'to': to}),
    ) as Map<String, dynamic>;
    return RankingChart.fromJson(json);
  }
}
