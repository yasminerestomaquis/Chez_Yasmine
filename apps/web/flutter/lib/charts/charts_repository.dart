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

  /// Codes `charts.*` accordés à l'utilisateur courant (voir
  /// `ChartsController.myPermissions`) — l'écran Graphiques masque les autres.
  Future<Set<String>> getMyPermissions() async {
    final json = await _api.get('$_base/permissions') as Map<String, dynamic>;
    return (json['permissions'] as List<dynamic>).cast<String>().toSet();
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
    Set<String>? productIds,
  }) async {
    final json = await _api.get(
      '$_base/weekly-by-product',
      query: _query({
        'metric': metric,
        'weekStart': weekStart,
        'productIds': (productIds == null || productIds.isEmpty) ? null : productIds.join(','),
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

  Future<StockLotsChart> getStockLots({
    required List<String> productIds,
  }) async {
    final json = await _api.get(
      '$_base/stock-lots',
      query: _query({'productIds': productIds.join(',')}),
    ) as Map<String, dynamic>;
    return StockLotsChart.fromJson(json);
  }

  Future<List<OutOfStockProduct>> getOutOfStockProducts() async {
    final json =
        await _api.get('$_base/out-of-stock-products') as List<dynamic>;
    return json
        .map((e) => OutOfStockProduct.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<WeeklyChart> getExpensesWeekly({String? weekStart}) async {
    final json = await _api.get(
      '$_base/expenses/weekly',
      query: _query({'weekStart': weekStart}),
    ) as Map<String, dynamic>;
    return WeeklyChart.fromJson(json);
  }

  /// [categories] vide/nul : une série par catégorie (comportement par
  /// défaut). Une ou plusieurs catégories fournies : une seule série, somme
  /// jour par jour de ces catégories — sélection multiple, même principe que
  /// [getWeeklyByCategory].
  Future<WeeklyChart> getExpensesWeeklyByCategory({
    String? weekStart,
    Set<String>? categories,
  }) async {
    final json = await _api.get(
      '$_base/expenses/weekly-by-category',
      query: _query({
        'weekStart': weekStart,
        'categories': (categories == null || categories.isEmpty)
            ? null
            : categories.join(','),
      }),
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

  /// Listing "Stock actif" (module Stock, bouton d'export réservé au Super
  /// Administrateur — demande utilisateur du 2026-09-25) : un produit = une
  /// ligne, agrégée sur ses seuls lots actifs. [categoryIds] : filtre optionnel
  /// (sélection multiple) parmi les catégories éligibles — les catégories à
  /// prix variable (Plats africains/Poissons/Poulets) sont de toute façon
  /// toujours exclues côté serveur.
  Future<List<ActiveStockListingRow>> getActiveStockListing({
    Set<String>? categoryIds,
  }) async {
    final json = await _api.get(
      '$_base/active-stock-listing',
      query: _query({
        'categoryIds': (categoryIds == null || categoryIds.isEmpty) ? null : categoryIds.join(','),
      }),
    ) as List<dynamic>;
    return json
        .map((e) => ActiveStockListingRow.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Export PDF du même listing, tableau à quadrillage complet.
  Future<({List<int> bytes, String? filename})> exportActiveStockListingPdf({
    Set<String>? categoryIds,
  }) {
    return _api.getBytes(
      '$_base/active-stock-listing.pdf',
      query: _query({
        'categoryIds': (categoryIds == null || categoryIds.isEmpty) ? null : categoryIds.join(','),
      }),
    );
  }
}
