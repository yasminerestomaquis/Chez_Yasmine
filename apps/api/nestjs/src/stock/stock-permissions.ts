/**
 * Visibilité du groupe « Valeur du stock » (prix d'achat/prix de vente du
 * stock filtré par catégorie) dans le module Stock — permission dédiée,
 * distincte de `stock.view`/`stock.manage`, pour que ce chiffre puisse être
 * accordé ou refusé rôle par rôle depuis « Gestion des permissions » (demande
 * utilisateur du 2026-09-22). Par défaut, seul le Super Administrateur la
 * porte (voir supabase/seed/001_roles_permissions.sql).
 */
export const STOCK_VALUE_PERMISSION = 'stock.view_value';

/**
 * Listing "Stock actif" (bouton d'export PDF de l'AppBar du module Stock —
 * demande utilisateur du 2026-09-25) — même principe que `STOCK_VALUE_PERMISSION`
 * ci-dessus : permission dédiée, accordée/révocable rôle par rôle depuis
 * « Gestion des permissions ». Par défaut, seul le Super Administrateur la
 * porte (voir supabase/seed/001_roles_permissions.sql). La route elle-même
 * vit dans `ChartsController` (`GET .../charts/active-stock-listing[.pdf]`,
 * réutilise les lots FIFO déjà calculés là), mais le code `stock.*` la classe
 * sous le module Stock dans la matrice de permissions
 * (`modulePrefixOf`, `lib/users/permission_grouping.dart`), pas Graphiques.
 */
export const STOCK_ACTIVE_LISTING_PERMISSION = 'stock.active_listing';

export const ALL_STOCK_PERMISSIONS: string[] = [STOCK_VALUE_PERMISSION, STOCK_ACTIVE_LISTING_PERMISSION];

/** Ne garde que les permissions Stock à bascule client parmi [granted]. */
export function stockPermissionsOf(granted: Set<string>): string[] {
  return ALL_STOCK_PERMISSIONS.filter((code) => granted.has(code));
}
