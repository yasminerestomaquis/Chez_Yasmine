/**
 * Visibilité du groupe « Valeur du stock » (prix d'achat/prix de vente du
 * stock filtré par catégorie) dans le module Stock — permission dédiée,
 * distincte de `stock.view`/`stock.manage`, pour que ce chiffre puisse être
 * accordé ou refusé rôle par rôle depuis « Gestion des permissions » (demande
 * utilisateur du 2026-09-22). Par défaut, seul le Super Administrateur la
 * porte (voir supabase/seed/001_roles_permissions.sql).
 */
export const STOCK_VALUE_PERMISSION = 'stock.view_value';

export const ALL_STOCK_PERMISSIONS: string[] = [STOCK_VALUE_PERMISSION];

/** Ne garde que les permissions Stock à bascule client parmi [granted]. */
export function stockPermissionsOf(granted: Set<string>): string[] {
  return ALL_STOCK_PERMISSIONS.filter((code) => granted.has(code));
}
