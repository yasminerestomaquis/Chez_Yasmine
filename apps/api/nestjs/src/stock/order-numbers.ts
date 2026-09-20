import { BadRequestException } from '@nestjs/common';
import type { PrismaService } from '../prisma/prisma.service.js';
import { computeFifoLots, type StockLotMovementType } from './stock-lots.js';

/** N° de commande proposés pour un produit et valeur par défaut (demande utilisateur du 2026-09-20). */
export interface OrderNumberChoices {
  /** Vrai si le produit est d'une catégorie à prix par casier : le N° de la commande est alors obligatoire. */
  required: boolean;
  /** N° des commandes (Achats) contenant ce produit, du plus récent au plus ancien. */
  options: number[];
  /** Commande du dernier lot actif, sinon du lot le plus récent, sinon la dernière commande. */
  defaultOrderNumber: number | null;
}

/**
 * Choix de N° de commande d'un produit. La valeur par défaut est la commande
 * du dernier lot actif (« dernière valeur active »), à défaut du lot le plus
 * récent (« récente »), à défaut de la commande la plus récente.
 */
export async function orderNumberChoices(
  prisma: Pick<PrismaService, 'product' | 'purchase' | 'stockMovement'>,
  establishmentId: string,
  productId: string,
): Promise<OrderNumberChoices> {
  const product = await prisma.product.findFirst({
    where: { id: productId, establishmentId },
    select: { category: { select: { hasCasePricing: true } } },
  });
  const required = product?.category?.hasCasePricing ?? false;
  if (!required) return { required: false, options: [], defaultOrderNumber: null };

  const purchases = await prisma.purchase.findMany({
    where: { establishmentId, items: { some: { productId } } },
    select: { orderNumber: true },
  });
  const options = [...new Set(purchases.map((p) => p.orderNumber))].sort((a, b) => b - a);

  const movements = await prisma.stockMovement.findMany({
    where: { productId },
    orderBy: { createdAt: 'asc' },
    select: { type: true, quantity: true, createdAt: true, reason: true },
  });
  const lots = computeFifoLots(
    movements.map((m) => ({
      type: m.type as StockLotMovementType,
      quantity: m.quantity.toNumber(),
      createdAt: m.createdAt,
      reason: m.reason,
    })),
  ).filter((lot) => lot.referenceNumber != null && options.includes(lot.referenceNumber));
  const latest = (list: typeof lots) =>
    list.reduce<(typeof lots)[number] | null>((a, b) => (a && a.receivedAt >= b.receivedAt ? a : b), null);
  const chosen = latest(lots.filter((lot) => lot.status === 'actif')) ?? latest(lots);

  return { required, options, defaultOrderNumber: chosen?.referenceNumber ?? options[0] ?? null };
}

/** Exige un N° de commande valide pour un produit à prix par casier ; `undefined` si le produit n'est pas concerné. */
export async function resolveOrderNumber(
  prisma: Pick<PrismaService, 'purchase'>,
  establishmentId: string,
  product: { id: string; category?: { hasCasePricing: boolean } | null },
  orderNumber: number | null | undefined,
): Promise<number | undefined> {
  if (!product.category?.hasCasePricing) return undefined;
  if (!orderNumber) throw new BadRequestException('N° de la commande obligatoire pour ce produit');
  const purchase = await prisma.purchase.findFirst({
    where: { establishmentId, orderNumber, items: { some: { productId: product.id } } },
    select: { id: true },
  });
  if (!purchase) throw new BadRequestException(`Aucune commande n°${orderNumber} ne contient ce produit`);
  return orderNumber;
}

/** Motif de mouvement rattachant le mouvement au lot de la commande (même gabarit que Achats : « Commande n°X »). */
export function reasonWithOrder(orderNumber: number | undefined, reason: string | null | undefined): string | undefined {
  if (orderNumber === undefined) return reason ?? undefined;
  return `Commande n°${orderNumber}${reason ? ` — ${reason}` : ''}`;
}
