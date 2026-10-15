/**
 * Groupes de recettes dont la SAISIE (vente en Caisse ou ajout à une addition)
 * peut être accordée ou refusée rôle par rôle depuis « Gestion des
 * permissions » (demande utilisateur du 2026-10-15) :
 * - `beverages` : boissons sans Gbêlê (catégories à prix par casier : Bières, Vins, Sucreries) ;
 * - `gbele` : Gbêlê (catégorie boisson hors casier, `isBeverage`) ;
 * - `plats` : plats (catégories à prix variable : Poulets, Poissons, Plats africains).
 *
 * Même découpage que les recettes de l'Accueil (`ReportsService.
 * paymentCategoryBreakdown`). Un produit hors de ces groupes (sans catégorie,
 * ou catégorie à prix fixe ordinaire) n'est soumis qu'à `pos.sell`.
 */
export type SellGroup = 'beverages' | 'gbele' | 'plats';

export const SELL_GROUP_PERMISSIONS: Record<SellGroup, string> = {
  beverages: 'pos.sell_beverages',
  gbele: 'pos.sell_gbele',
  plats: 'pos.sell_plats',
};

export const SELL_GROUP_LABELS: Record<SellGroup, string> = {
  beverages: 'boissons (hors Gbêlê)',
  gbele: 'Gbêlê',
  plats: 'plats',
};

export interface CategoryFlags {
  hasCasePricing: boolean;
  hasVariablePricing: boolean;
  isBeverage: boolean;
}

/** Groupe de recettes d'une catégorie, ou `null` si le produit n'en relève d'aucun. */
export function sellGroupOf(category: CategoryFlags | null | undefined): SellGroup | null {
  if (!category) return null;
  if (category.hasVariablePricing) return 'plats';
  if (category.isBeverage && !category.hasCasePricing) return 'gbele';
  if (category.hasCasePricing) return 'beverages';
  return null;
}

/** Groupes distincts touchés par une liste de produits (ordre d'apparition). */
export function sellGroupsOf(products: { category: CategoryFlags | null }[]): SellGroup[] {
  const groups: SellGroup[] = [];
  for (const product of products) {
    const group = sellGroupOf(product.category);
    if (group && !groups.includes(group)) groups.push(group);
  }
  return groups;
}

/** Codes `pos.sell_*` à bascule client parmi [granted]. */
export function sellGroupPermissionsOf(granted: Set<string>): string[] {
  return Object.values(SELL_GROUP_PERMISSIONS).filter((code) => granted.has(code));
}
