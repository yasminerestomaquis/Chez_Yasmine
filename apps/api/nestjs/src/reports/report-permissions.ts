/**
 * Permissions à bascule client du module Rapports (demande utilisateur du
 * 2026-09-25) : jusqu'ici, `reports.view` gate toutes les routes du module
 * sans distinction — désormais chacun des trois boutons de l'AppBar
 * (« Boissons vendues », « Plats vendus », « Exporter ») a son propre code,
 * accordable/révocable rôle par rôle depuis « Gestion des permissions »,
 * même principe que `STOCK_VALUE_PERMISSION`/`chart-permissions.ts`.
 *
 * Par défaut, tout rôle qui porte déjà `reports.view` reçoit les trois (voir
 * supabase/seed/001_roles_permissions.sql) — aucun changement de
 * comportement tant qu'un bouton n'est pas explicitement refusé à un rôle.
 *
 * `reports.export` couvre le bouton dans son ensemble (menu « Exporter le
 * rapport (CSV) » + « Exporter une commande d'achat ») côté visibilité
 * client et gate `summary.csv` côté serveur ; l'export de commande d'achat
 * lui-même reste géré par ses propres permissions `purchases.*`
 * (`PurchasingModule`), module distinct — pas dupliqué ici.
 */
export const REPORTS_BEVERAGES_SOLD_PERMISSION = 'reports.beverages_sold';
export const REPORTS_PLATS_SOLD_PERMISSION = 'reports.plats_sold';
export const REPORTS_EXPORT_PERMISSION = 'reports.export';

export const ALL_REPORTS_PERMISSIONS: string[] = [
  REPORTS_BEVERAGES_SOLD_PERMISSION,
  REPORTS_PLATS_SOLD_PERMISSION,
  REPORTS_EXPORT_PERMISSION,
];

/** Ne garde que les permissions Rapports à bascule client parmi [granted]. */
export function reportsPermissionsOf(granted: Set<string>): string[] {
  return ALL_REPORTS_PERMISSIONS.filter((code) => granted.has(code));
}
