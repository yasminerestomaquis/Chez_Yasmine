/**
 * Valeur des pertes dans les statistiques Espèces/Mobile Money × Boissons
 * sans Gbêlê/Gbêlê/Plats de l'Accueil (`ReportsService.
 * paymentCategoryBreakdown`) — demande utilisateur du 2026-09-20 : une perte
 * enregistrée à une date précise compte, à son prix de vente, dans le groupe
 * de la catégorie de son produit et **uniquement côté Mobile Money** (jamais
 * Espèces). Le groupe Boissons s'est scindé en deux le 2026-09-24 (Boissons
 * sans Gbêlê / Gbêlê) — voir `lossGroupOf`.
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

/**
 * Même critère que les ventes (`ReportsService.paymentCategoryBreakdown`) :
 * `hasCasePricing` (Bières/Vins/Sucreries) → Boissons sans Gbêlê,
 * `isBeverage` sans `hasCasePricing` (ex. Gbêlê) → Gbêlê, isolé le
 * 2026-09-24 (auparavant fusionné avec Boissons), `hasVariablePricing` → Plats.
 */
export function lossGroupOf(
  category: LossForRevenue['product']['category'],
): 'boissonsSansGbele' | 'gbele' | 'plats' | null {
  if (category?.hasCasePricing) return 'boissonsSansGbele';
  if (category?.isBeverage) return 'gbele';
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
 * Cumul de la valeur des pertes par groupe. Une perte dont le produit n'est
 * dans aucun des trois groupes (catégorie fixe hors groupe, ou sans
 * catégorie) n'est comptée nulle part, comme une ligne de vente de même nature.
 */
export function lossRevenueByGroup(
  losses: LossForRevenue[],
): { boissonsSansGbele: number; gbele: number; plats: number } {
  const totals = { boissonsSansGbele: 0, gbele: 0, plats: 0 };
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
