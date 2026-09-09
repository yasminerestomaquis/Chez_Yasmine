export interface CostableProduct {
  purchasePrice: { toNumber(): number } | null;
  bottlesPerCase: number | null;
  purchasePricePerCase: { toNumber(): number } | null;
  category: { hasCasePricing: boolean } | null;
}

/**
 * Coût unitaire "actuel" d'un produit — utilisé partout où un coût de vente
 * ou de perte est estimé (rapports, graphiques Bénéfices). Pour une
 * catégorie à prix par casier (Bières, Vins, Sucreries — voir
 * docs/api/catalog.md), le prix d'achat par casier est la source de vérité
 * du coût, jamais purchasePrice ("prix d'achat par bouteille") — décision
 * explicite de l'utilisateur (2026-09-09). Repli sur purchasePrice si la
 * catégorie n'est pas à prix par casier, ou si ces champs ne sont pas encore
 * renseignés sur la fiche produit.
 */
export function effectiveUnitCost(product: CostableProduct): number {
  if (product.category?.hasCasePricing && product.bottlesPerCase && product.purchasePricePerCase) {
    return product.purchasePricePerCase.toNumber() / product.bottlesPerCase;
  }
  return product.purchasePrice?.toNumber() ?? 0;
}
