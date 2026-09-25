/// Les 17 permissions de graphiques (`charts.<sous-module>_<graphique>`) —
/// miroir de `ALL_CHART_PERMISSIONS`
/// (apps/api/nestjs/src/charts/chart-permissions.ts). Sert de repli quand la
/// liste réellement accordée n'a pas pu être chargée.
const Set<String> allChartPermissions = {
  'charts.revenue_daily',
  'charts.revenue_by_category',
  'charts.revenue_by_product',
  'charts.revenue_top',
  'charts.revenue_monthly',
  'charts.profit_daily',
  'charts.profit_by_category',
  'charts.profit_by_product',
  'charts.profit_top',
  'charts.profit_monthly',
  'charts.stock_lots',
  'charts.stock_out',
  'charts.profit_meals_listing',
  'charts.expenses_daily',
  'charts.expenses_by_category',
  'charts.expenses_top',
  'charts.expenses_monthly',
};
