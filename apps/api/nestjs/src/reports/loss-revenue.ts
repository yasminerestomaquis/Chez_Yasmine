/**
 * Valorisation d'une perte pour l'affichage (module Pertes) et le décompte du
 * stock — jamais pour les recettes de l'Accueil : `ReportsService.
 * paymentCategoryBreakdown` ne compte plus les pertes depuis le 2026-09-27
 * (revenu sur la décision du 2026-09-20, qui les ajoutait côté Mobile Money —
 * voir docs/api/reports.md), une perte n'étant pas une vente encaissée.
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
