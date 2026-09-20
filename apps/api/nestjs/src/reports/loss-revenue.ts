/**
 * Valeur des pertes dans les statistiques Espèces/Mobile Money × Boissons/Plats
 * de l'Accueil (`ReportsService.paymentCategoryBreakdown`) — demande
 * utilisateur du 2026-09-20 : une perte enregistrée à une date précise compte,
 * à son prix de vente, dans le groupe (Boissons ou Plats) de la catégorie de
 * son produit et **uniquement côté Mobile Money** (jamais Espèces).
 */
export interface LossForRevenue {
  quantity: { toNumber(): number };
  sellAsUnit?: boolean;
  product: {
    salePrice: { toNumber(): number } | null;
    unitSalePrice?: { toNumber(): number } | null;
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
 * Prix de vente unitaire d'un produit pour valoriser une perte : le prix à
 * l'unité si la perte est déclarée « Unité » (`sellAsUnit`, produit vendu par
 * lot ET à l'unité), sinon `salePrice`,
 * sinon `referenceSalePrice` (produit dont le prix se saisit à chaque vente,
 * ex. Gbêlê), sinon 0 — même règle que `LossesService.list`.
 */
export function lossUnitSalePrice(product: Omit<LossForRevenue['product'], 'category'>, sellAsUnit = false): number {
  if (sellAsUnit && product.unitSalePrice != null) return product.unitSalePrice.toNumber();
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
    totals[group] += loss.quantity.toNumber() * lossUnitSalePrice(loss.product, loss.sellAsUnit);
  }
  return totals;
}

/** Taille du lot lue dans `Product.unit` (« 3 » pour « Lot (3) ») ; 1 si absente ou illisible. */
export function lotSize(unit: string | null | undefined): number {
  const n = Number.parseInt((unit ?? '').trim(), 10);
  return Number.isFinite(n) && n > 0 ? n : 1;
}

/**
 * Unités retirées du stock par une perte : « Lot » d'un produit vendu par lot
 * ET à l'unité = quantité × taille du lot (3 unités par lot pour Lot (3)),
 * « Unité » = quantité — demande utilisateur du 2026-09-20. Sans prix à
 * l'unité, la quantité est déjà en unités de stock.
 */
export function lossStockUnits(
  product: { unit: string | null; unitSalePrice: { toNumber(): number } | null },
  quantity: number,
  sellAsUnit: boolean,
): number {
  if (product.unitSalePrice == null || sellAsUnit) return quantity;
  return quantity * lotSize(product.unit);
}
