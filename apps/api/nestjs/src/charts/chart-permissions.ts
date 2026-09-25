import type { ChartMetric } from './dto/chart-query.dto.js';

/**
 * Une permission par graphique (décision utilisateur du 2026-09-20, module
 * Graphiques dans « Gestion des permissions ») — `charts.<sous-module>_<graphique>`.
 * Remplace `reports.view` sur les routes de ce module ; les rôles qui portaient
 * `reports.view` reçoivent toutes ces permissions (voir
 * supabase/seed/001_roles_permissions.sql), donc rien ne change tant
 * qu'un graphique n'est pas explicitement refusé à un rôle.
 */
export type MetricChartKind = 'daily' | 'by_category' | 'by_product' | 'top' | 'monthly';
export type ExpenseChartKind = 'daily' | 'by_category' | 'top' | 'monthly';

const METRIC_KEY: Record<ChartMetric, string> = { revenue: 'revenue', profit: 'profit' };

export function metricChartPermission(metric: ChartMetric, kind: MetricChartKind): string {
  return `charts.${METRIC_KEY[metric]}_${kind}`;
}

export function expenseChartPermission(kind: ExpenseChartKind): string {
  return `charts.expenses_${kind}`;
}

export const STOCK_LOTS_PERMISSION = 'charts.stock_lots';
export const STOCK_OUT_PERMISSION = 'charts.stock_out';

/**
 * Listing "Repas" (module Graphiques > Bénéfices, bouton d'export PDF —
 * demande utilisateur du 2026-09-25) : granularité "par graphique" comme les
 * 16 permissions ci-dessus, ajoutée au même endroit pour rester groupée sous
 * Graphiques > Bénéfices dans "Gestion des permissions"
 * (`modulePrefixOf`/`permission_grouping.dart` regroupe par préfixe de code,
 * `charts.profit_*` → Bénéfices, quel que soit le suffixe).
 */
export const PROFIT_MEALS_LISTING_PERMISSION = 'charts.profit_meals_listing';

/** Tous les codes de permission de graphiques (17) — utile pour les tests et la documentation. */
export const ALL_CHART_PERMISSIONS: string[] = [
  ...(['revenue', 'profit'] as const).flatMap((metric) =>
    (['daily', 'by_category', 'by_product', 'top', 'monthly'] as const).map((kind) => `charts.${metric}_${kind}`),
  ),
  STOCK_LOTS_PERMISSION,
  STOCK_OUT_PERMISSION,
  PROFIT_MEALS_LISTING_PERMISSION,
  ...(['daily', 'by_category', 'top', 'monthly'] as const).map((kind) => `charts.expenses_${kind}`),
];

/** Ne garde que les permissions de graphiques parmi [granted], dans l'ordre canonique. */
export function chartPermissionsOf(granted: Set<string>): string[] {
  return ALL_CHART_PERMISSIONS.filter((code) => granted.has(code));
}
