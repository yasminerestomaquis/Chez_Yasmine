import 'package:flutter_test/flutter_test.dart';

import 'package:chez_yasmine/charts/chart_models_permissions.dart';

void main() {
  test('les 16 codes de graphiques sont distincts et répartis par sous-module', () {
    expect(allChartPermissions, hasLength(16));
    expect(allChartPermissions.where((c) => c.startsWith('charts.revenue_')), hasLength(5));
    expect(allChartPermissions.where((c) => c.startsWith('charts.profit_')), hasLength(5));
    expect(allChartPermissions.where((c) => c.startsWith('charts.stock_')), hasLength(2));
    expect(allChartPermissions.where((c) => c.startsWith('charts.expenses_')), hasLength(4));
  });
}
