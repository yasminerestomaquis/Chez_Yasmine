import { BadRequestException } from '@nestjs/common';

/**
 * Vente d'un produit à « prix de référence variable » (`Product.
 * referenceSalePrice`, ex. Gbêlê : prix d'achat connu au litre, prix de
 * vente saisi à chaque vente — décision utilisateur du 2026-09-17, formule
 * précisée le 2026-09-24) : le caissier saisit un MONTANT payé (ex. 100
 * FCFA), jamais une quantité — le serveur en déduit la quantité (ex. litres)
 * en la divisant par le prix de référence (100 / 3000 = 0,033 L), puis
 * recalcule un prix unitaire tel que `quantity × unitPrice` reproduise
 * exactement le montant saisi, même après l'arrondi de `quantity` à 2
 * décimales (précision de la colonne `sale_items.quantity`/
 * `stock_movements.quantity`, `Decimal(12,2)`) — le client n'est jamais
 * source de vérité sur le prix ni sur la quantité pour ce cas, seulement sur
 * le montant réellement encaissé.
 *
 * Un montant trop faible pour représenter au moins 0,01 unité (ex. moins de
 * 15 FCFA à 3 000 FCFA/L) est refusé plutôt que silencieusement arrondi à 0,
 * ce qui décrémenterait le stock de zéro tout en facturant un montant non
 * nul — une vente ne peut jamais porter sur une quantité nulle (voir
 * `pos-math.ts#lineTotal`).
 */
export function resolveReferencePriceLine(
  referenceSalePrice: number,
  amountPaid: number,
  productName: string,
): { quantity: number; unitPrice: number } {
  if (!Number.isFinite(amountPaid) || amountPaid <= 0) {
    throw new BadRequestException(`Montant payé invalide pour ${productName}`);
  }
  const quantity = Math.round((amountPaid / referenceSalePrice) * 100) / 100;
  if (quantity <= 0) {
    throw new BadRequestException(`Montant trop faible pour ${productName} (quantité arrondie à 0)`);
  }
  return { quantity, unitPrice: amountPaid / quantity };
}
