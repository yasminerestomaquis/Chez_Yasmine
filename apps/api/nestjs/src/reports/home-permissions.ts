/**
 * Permissions d'AFFICHAGE du tableau de bord (Accueil), une par rubrique —
 * demande utilisateur du 2026-10-15 : accorder ou refuser, rôle par rôle
 * depuis « Gestion des permissions » (module Accueil), chaque carte de
 * l'Accueil. Remplace la comparaison codée en dur sur le rôle Serveur.
 *
 * Par défaut (supabase/seed/001_roles_permissions.sql) tout rôle qui porte
 * `reports.view` reçoit les 14 codes, sauf le Serveur qui garde exactement ce
 * qu'il voyait déjà : recettes boissons sans Gbêlê / Gbêlê et leur détail par
 * mode de paiement — aucun changement de comportement tant que rien n'est
 * personnalisé.
 *
 * Il s'agit de droits d'affichage : les routes `summary` et
 * `payment-category-breakdown` restent gardées par `reports.view`.
 */
export const HOME_PERMISSIONS = [
  'home.total_sales',
  'home.cash',
  'home.mobile_money',
  'home.orders',
  'home.stock_alerts',
  'home.revenue_beverages',
  'home.revenue_gbele',
  'home.revenue_plats',
  'home.detail_beverages_cash',
  'home.detail_beverages_mobile',
  'home.detail_gbele_cash',
  'home.detail_gbele_mobile',
  'home.detail_plats_cash',
  'home.detail_plats_mobile',
] as const;

/** Vrai si le rôle voit au moins une rubrique de l'Accueil. */
export function canViewHome(granted: Set<string>): boolean {
  return HOME_PERMISSIONS.some((code) => granted.has(code));
}

/** Permission d'affichage de chaque champ de `payment-category-breakdown`. */
export const HOME_BREAKDOWN_FIELD_PERMISSIONS = {
  totalRevenue: 'home.total_sales',
  cashRevenue: 'home.cash',
  mobileMoneyRevenue: 'home.mobile_money',
  boissonsSansGbeleRevenue: 'home.revenue_beverages',
  gbeleRevenue: 'home.revenue_gbele',
  platsRevenue: 'home.revenue_plats',
  boissonsSansGbeleCash: 'home.detail_beverages_cash',
  boissonsSansGbeleMobileMoney: 'home.detail_beverages_mobile',
  gbeleCash: 'home.detail_gbele_cash',
  gbeleMobileMoney: 'home.detail_gbele_mobile',
  platsCash: 'home.detail_plats_cash',
  platsMobileMoney: 'home.detail_plats_mobile',
} as const;

/**
 * Ne laisse sortir que les chiffres que le rôle a le droit de voir : tout champ
 * dont la rubrique d'Accueil n'est pas accordée est mis à 0 (l'écran masque de
 * toute façon la carte). Un rôle sans `reports.view` ne reçoit ainsi jamais un
 * chiffre qu'on ne lui a pas accordé, même en appelant la route à la main.
 */
export function maskBreakdown<T extends Record<keyof typeof HOME_BREAKDOWN_FIELD_PERMISSIONS, number>>(
  breakdown: T,
  granted: Set<string>,
): T {
  const masked = { ...breakdown };
  for (const [field, code] of Object.entries(HOME_BREAKDOWN_FIELD_PERMISSIONS)) {
    if (!granted.has(code)) (masked as Record<string, number>)[field] = 0;
  }
  return masked;
}

/** Ne garde que les permissions Accueil parmi [granted]. */
export function homePermissionsOf(granted: Set<string>): string[] {
  return HOME_PERMISSIONS.filter((code) => granted.has(code));
}
