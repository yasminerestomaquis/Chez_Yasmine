import { lossStockUnits } from '../reports/loss-revenue.js';

/**
 * Unités de STOCK retirées (ou restituées) par une ligne de vente.
 *
 * Le stock d'un produit se compte en unités (bouteilles). Pour un produit
 * vendu par lot ET à l'unité (`unitSalePrice` renseigné, ex. Despé 33 :
 * « Lot (3) — 2 000 F » / « Unité — 700 F »), une ligne « Lot » de quantité 2
 * consomme 2 × 3 = 6 bouteilles, une ligne « Unité » de quantité 2 en consomme
 * 2. Sans prix à l'unité, la quantité est déjà en unités de stock.
 *
 * Avant le 2026-10-15, la caisse décrémentait la quantité de la ligne telle
 * quelle : un lot de 3 ne retirait qu'une bouteille du stock (constaté sur
 * Despé 33 et Heineken 33). Même règle que pour les pertes
 * (`lossStockUnits`), dont elle reprend la convention — la taille du lot est
 * lue dans `Product.unit` (« 3 » pour « Lot (3) »).
 */
export function saleStockUnits(
  product: { unit: string | null; unitSalePrice: { toNumber(): number } | null } | null | undefined,
  quantity: number,
  sellAsUnit: boolean,
): number {
  if (!product) return quantity;
  return lossStockUnits(product, quantity, sellAsUnit);
}
