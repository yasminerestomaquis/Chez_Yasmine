import { describe, expect, it } from 'vitest';
import {
  ALL_CHART_PERMISSIONS,
  chartPermissionsOf,
  expenseChartPermission,
  metricChartPermission,
  STOCK_LOTS_PERMISSION,
  STOCK_OUT_PERMISSION,
} from './chart-permissions.js';

describe('chart-permissions', () => {
  it('liste 16 permissions distinctes : 5 Recettes, 5 Bénéfices, 2 Stock, 4 Dépenses', () => {
    expect(ALL_CHART_PERMISSIONS).toHaveLength(16);
    expect(new Set(ALL_CHART_PERMISSIONS).size).toBe(16);
    expect(ALL_CHART_PERMISSIONS.filter((c) => c.startsWith('charts.revenue_'))).toHaveLength(5);
    expect(ALL_CHART_PERMISSIONS.filter((c) => c.startsWith('charts.profit_'))).toHaveLength(5);
    expect(ALL_CHART_PERMISSIONS.filter((c) => c.startsWith('charts.stock_'))).toHaveLength(2);
    expect(ALL_CHART_PERMISSIONS.filter((c) => c.startsWith('charts.expenses_'))).toHaveLength(4);
  });

  it('le code dépend de la métrique (Recettes/Bénéfices) et du type de graphique', () => {
    expect(metricChartPermission('revenue', 'daily')).toBe('charts.revenue_daily');
    expect(metricChartPermission('profit', 'by_category')).toBe('charts.profit_by_category');
    expect(expenseChartPermission('top')).toBe('charts.expenses_top');
  });

  it('tout code produit par une route figure dans la liste canonique', () => {
    const produced = [
      metricChartPermission('revenue', 'daily'),
      metricChartPermission('revenue', 'by_category'),
      metricChartPermission('revenue', 'by_product'),
      metricChartPermission('revenue', 'top'),
      metricChartPermission('revenue', 'monthly'),
      metricChartPermission('profit', 'daily'),
      metricChartPermission('profit', 'by_category'),
      metricChartPermission('profit', 'by_product'),
      metricChartPermission('profit', 'top'),
      metricChartPermission('profit', 'monthly'),
      STOCK_LOTS_PERMISSION,
      STOCK_OUT_PERMISSION,
      expenseChartPermission('daily'),
      expenseChartPermission('by_category'),
      expenseChartPermission('top'),
      expenseChartPermission('monthly'),
    ];
    expect(new Set(produced)).toEqual(new Set(ALL_CHART_PERMISSIONS));
  });

  it('chartPermissionsOf ne garde que les permissions de graphiques accordées', () => {
    const granted = new Set(['pos.sell', 'charts.revenue_daily', 'charts.stock_out', 'reports.view']);
    expect(chartPermissionsOf(granted)).toEqual(['charts.revenue_daily', 'charts.stock_out']);
  });
});
