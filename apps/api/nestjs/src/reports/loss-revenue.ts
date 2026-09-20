/**
 * Valeur des pertes dans les statistiques Espèces/Mobile Money × Boissons/Plats
 * de l'Accueil (`ReportsService.paymentCategoryBreakdown`) — demande
 * utilisateur du 2026-09-20 : une perte enregistrée à une date précise compte,
 * à son prix de vente, dans le groupe (Boissons ou Plats) de la catégorie de
 * son produit et **uniquement côté Mobile Money** (jamais Espèces).
 */
export interface LossForRevenue {
  quantity: { toNumber(): number };
  product: {
    salePrice: { toNumber(): number } | null;
    referenceSalePrice: { toNumber(): number } | null;
    category: { hasCasePricing: boolean; hasVariablePricing: boolean; isBeverage: boolean } | null;
  };
}

/** Même critère Boissons/Plats que les ventes (`hasCasePricing || isBeverage` / `hasVariablePricing`). */
export function lossGroupOf(category: LossForRevenue['product']['category']): 'boissons' | 'plats' | null {
  if (category?.hasCasePricing || category?.isBeverage) return 'boissons';
  if (category?.hasVariablePricing) return 'plats';
  return null;
}

/**
 * Prix de vente unitaire d'un produit pour valoriser une perte : `salePrice`,
 * sinon `referenceSalePrice` (produit dont le prix se saisit à chaque vente,
 * ex. Gbêlê), sinon 0 — même règle que `LossesService.list`.
 */
export function lossUnitSalePrice(product: LossForRevenue['product']): number {
  return product.salePrice?.toNumber() ?? product.referenceSalePrice?.toNumber() ?? 0;
}

/**
 * Cumul de la valeur des pertes par groupe. Une perte dont le produit n'est ni
 * Boissons ni Plats (catégorie fixe hors groupe, ou sans catégorie) n'est
 * comptée nulle part, comme une ligne de vente de même nature.
 */
export function lossRevenueByGroup(losses: LossForRevenue[]): { boissons: number; plats: number } {
  const totals = { boissons: 0, plats: 0 };
  for (const loss of losses) {
    const group = lossGroupOf(loss.product.category);
    if (group === null) continue;
    totals[group] += loss.quantity.toNumber() * lossUnitSalePrice(loss.product);
  }
  return totals;
}
