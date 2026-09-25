import 'package:flutter_test/flutter_test.dart';

import 'package:chez_yasmine/charts/chart_models_permissions.dart';

void main() {
  test('les 17 codes de graphiques sont distincts et répartis par sous-module', () {
    expect(allChartPermissions, hasLength(17));
    expect(allChartPermissions.where((c) => c.startsWith('charts.revenue_')), hasLength(5));
    // 5 graphiques Bénéfices + charts.profit_meals_listing (listing Repas,
    // 2026-09-25) : namespacé sous charts.profit_ pour se regrouper sous
    // Bénéfices dans "Gestion des permissions" (modulePrefixOf), bien que ce
    // ne soit pas un graphique daily/by_category/by_product/top/monthly.
    expect(allChartPermissions.where((c) => c.startsWith('charts.profit_')), hasLength(6));
    expect(allChartPermissions.where((c) => c.startsWith('charts.stock_')), hasLength(2));
    expect(allChartPermissions.where((c) => c.startsWith('charts.expenses_')), hasLength(4));
  });
}
