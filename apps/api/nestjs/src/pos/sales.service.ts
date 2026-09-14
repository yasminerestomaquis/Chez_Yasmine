import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import { ActivityNotifierService } from '../notifications/activity-notifier.service.js';
import { applyCreditSale } from './credit-math.js';
import type { CreateSaleDto } from './dto/create-sale.dto.js';
import { computeCartTotals, validatePayments, type CartLine } from './pos-math.js';

@Injectable()
export class SalesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly activityNotifier: ActivityNotifierService,
  ) {}

  async create(establishmentId: string, userId: string, dto: CreateSaleDto) {
    // Idempotent replay: a client-supplied id lets the same offline sale be
    // resubmitted safely (network retry, sync queue) without double-charging
    // stock or creating a duplicate transaction.
    if (dto.id) {
      const existing = await this.prisma.sale.findFirst({
        where: { id: dto.id, establishmentId },
        include: { items: true, payments: true },
      });
      if (existing) return existing;
    }

    const productIds = [...new Set(dto.items.map((i) => i.productId))];
    const products = await this.prisma.product.findMany({ where: { id: { in: productIds }, establishmentId } });
    if (products.length !== productIds.length) {
      throw new BadRequestException("Un ou plusieurs produits n'appartiennent pas à cet établissement");
    }
    const productById = new Map(products.map((p) => [p.id, p]));

    // Agrégé par produit, pas par ligne : un produit à prix variable (Poulets/
    // Poissons/Plats africains) peut légitimement apparaître sur plusieurs
    // lignes du même panier (prix différents, voir PosPage._addToCart /
    // OrdersService.addItem) — vérifier chaque ligne isolément laisserait
    // passer une vente dont la SOMME des quantités dépasse le stock réel,
    // même si chaque ligne prise seule semble tenir dans le stock.
    const quantityByProductId = new Map<string, number>();
    for (const item of dto.items) {
      quantityByProductId.set(item.productId, (quantityByProductId.get(item.productId) ?? 0) + item.quantity);
    }
    // Contrôle rapide, avant d'ouvrir la transaction — message d'erreur clair
    // pour le cas courant. Ne suffit pas seul contre deux ventes concurrentes
    // du même produit (lu-puis-écrit, pas atomique) : voir le contrôle
    // conditionnel dans la transaction ci-dessous, qui est ce qui empêche
    // réellement une survente en cas de concurrence.
    for (const [productId, quantity] of quantityByProductId) {
      const product = productById.get(productId)!;
      if (product.stockQuantity.toNumber() < quantity) {
        throw new ConflictException(`Stock insuffisant pour ${product.name}`);
      }
    }

    // Un produit à prix fixe ignore tout unitPrice envoyé par le client (le
    // serveur reste seul juge du prix) ; un produit à prix variable (aucun
    // salePrice en catalogue) exige que le caissier l'ait saisi en caisse.
    // `sellAsUnit` ne fait pas exception à cette règle : le client indique
    // seulement laquelle des deux tarifications déjà connues du serveur
    // s'applique (jamais un montant) — voir SaleItemDto.sellAsUnit.
    const unitPriceByItemIndex = dto.items.map((item) => {
      const product = productById.get(item.productId)!;
      if (product.salePrice != null) {
        if (item.sellAsUnit && product.unitSalePrice != null) {
          return product.unitSalePrice.toNumber();
        }
        return product.salePrice.toNumber();
      }
      if (item.unitPrice == null) {
        throw new BadRequestException(`Prix de vente requis pour ${product.name} (catégorie à prix variable)`);
      }
      return item.unitPrice;
    });

    const lines: CartLine[] = dto.items.map((item, index) => ({
      productId: item.productId,
      unitPrice: unitPriceByItemIndex[index],
      quantity: item.quantity,
    }));

    let totals;
    try {
      totals = computeCartTotals(lines, dto.discount ?? { type: 'amount', value: 0 });
      validatePayments(dto.payments, totals.total, { customerId: dto.customerId });
    } catch (error) {
      throw new BadRequestException(error instanceof Error ? error.message : 'Vente invalide');
    }

    const creditAmount = dto.payments.filter((p) => p.method === 'credit').reduce((sum, p) => sum + p.amount, 0);
    let customer = dto.customerId
      ? await this.prisma.customer.findFirst({ where: { id: dto.customerId, establishmentId } })
      : null;
    if (dto.customerId && !customer) {
      throw new BadRequestException("Le client indiqué n'appartient pas à cet établissement");
    }
    let nextCreditBalance: number | null = null;
    if (creditAmount > 0) {
      try {
        nextCreditBalance = applyCreditSale(
          { balance: customer!.creditBalance.toNumber(), limit: customer!.creditLimit.toNumber() },
          creditAmount,
        );
      } catch (error) {
        throw new BadRequestException(error instanceof Error ? error.message : 'Crédit invalide');
      }
    }

    // Checking out a table's addition: the order must still be open, and we
    // close it + free its table once the sale is recorded (same transaction).
    let orderToClose: { id: string; tableId: string | null } | null = null;
    if (dto.orderId) {
      const order = await this.prisma.order.findFirst({ where: { id: dto.orderId, establishmentId } });
      if (!order) {
        throw new BadRequestException("L'addition indiquée n'appartient pas à cet établissement");
      }
      if (order.status !== 'open') {
        throw new ConflictException('Cette addition est déjà clôturée');
      }
      orderToClose = { id: order.id, tableId: order.tableId };
    }

    const sale = await this.prisma.$transaction(async (tx) => {
      // Décrémentation atomique et conditionnelle (une seule requête SQL par
      // produit, quantité déjà agrégée ci-dessus) : `updateMany` avec
      // `stockQuantity: { gte: quantity }` dans le WHERE ne modifie la ligne
      // que si le stock est encore suffisant AU MOMENT de l'exécution — le
      // verrou de ligne pris par Postgres pendant l'UPDATE empêche deux
      // transactions concurrentes de décrémenter le même produit sur la base
      // du même état de stock déjà lu. `count === 0` : le stock a changé
      // entre-temps (autre vente concurrente) et ne suffit plus.
      for (const [productId, quantity] of quantityByProductId) {
        const { count } = await tx.product.updateMany({
          where: { id: productId, stockQuantity: { gte: quantity } },
          data: { stockQuantity: { decrement: quantity } },
        });
        if (count === 0) {
          throw new ConflictException(`Stock insuffisant pour ${productById.get(productId)!.name}`);
        }
      }
      for (const item of dto.items) {
        await tx.stockMovement.create({
          data: { productId: item.productId, type: 'sale', quantity: item.quantity, createdBy: userId },
        });
      }

      const sale = await tx.sale.create({
        data: {
          id: dto.id,
          establishmentId,
          source: dto.source ?? 'pos',
          tableId: dto.tableId,
          orderId: dto.orderId,
          customerId: dto.customerId,
          subtotal: totals.subtotal,
          discount: totals.discount,
          total: totals.total,
          createdBy: userId,
          orderNumber: dto.orderNumber,
          marketNumber: dto.marketNumber,
          items: {
            create: dto.items.map((item, index) => ({
              productId: item.productId,
              name: productById.get(item.productId)!.name,
              quantity: item.quantity,
              unitPrice: unitPriceByItemIndex[index],
            })),
          },
          payments: { create: dto.payments.map((p) => ({ method: p.method, amount: p.amount })) },
        },
        include: { items: true, payments: true },
      });

      if (creditAmount > 0 && nextCreditBalance !== null) {
        await tx.customer.update({ where: { id: customer!.id }, data: { creditBalance: nextCreditBalance } });
        await tx.credit.create({ data: { customerId: customer!.id, saleId: sale.id, amount: creditAmount } });
      }

      if (orderToClose) {
        await tx.order.update({ where: { id: orderToClose.id }, data: { status: 'closed', closedAt: new Date() } });
        if (orderToClose.tableId) {
          // Ne libérer la table que si aucune autre addition n'y reste ouverte
          // (le multi-addition par table permet plusieurs encaissements
          // indépendants sur une même table — voir docs/api/tables.md).
          const remainingOpenOrders = await tx.order.count({
            where: { tableId: orderToClose.tableId, status: 'open' },
          });
          if (remainingOpenOrders === 0) {
            await tx.restaurantTable.update({ where: { id: orderToClose.tableId }, data: { status: 'free' } });
          }
        }
      }

      return sale;
    });
    // Noms des produits vendus (dédupliqués, dans l'ordre d'apparition) —
    // demande utilisateur du 2026-09-14 : savoir quoi s'est vendu, pas
    // seulement le montant, d'un simple coup d'œil sur la notification.
    const productNames = [...new Set(dto.items.map((item) => productById.get(item.productId)!.name))];
    await this.activityNotifier.notify(
      establishmentId,
      userId,
      'Nouvelle vente',
      `${productNames.join(', ')} — ${totals.total.toLocaleString('fr-FR')} FCFA`,
    );
    return sale;
  }

  /**
   * Suggestion éditable pour la caisse : N° de la dernière commande d'achat
   * enregistrée (toutes catégories/fournisseurs confondus), ou null s'il n'y
   * en a aucune. Jamais imposé côté serveur.
   *
   * Trié par `orderNumber` décroissant, pas par `createdAt` — même
   * convention que `PurchasesService.nextOrderNumber` : la date de création
   * d'une commande n'est pas forcément dans le même ordre que son N°
   * (une commande peut être saisie après coup), donc trier par date
   * risquerait de suggérer un numéro déjà dépassé.
   */
  async lastOrderNumber(establishmentId: string): Promise<number | null> {
    const last = await this.prisma.purchase.findFirst({
      where: { establishmentId },
      orderBy: { orderNumber: 'desc' },
      select: { orderNumber: true },
    });
    return last?.orderNumber ?? null;
  }

  /** Même principe pour le dernier N° de marché (dépense « Marché ») enregistré — voir `lastOrderNumber` pour pourquoi trier par le numéro plutôt que par date, et `ExpensesService.nextMarketNumber` pour la même convention côté Dépenses. */
  async lastMarketNumber(establishmentId: string): Promise<number | null> {
    const last = await this.prisma.expense.findFirst({
      where: { establishmentId, category: 'Marché', marketNumber: { not: null } },
      orderBy: { marketNumber: 'desc' },
      select: { marketNumber: true },
    });
    return last?.marketNumber ?? null;
  }

  async get(establishmentId: string, saleId: string) {
    const sale = await this.prisma.sale.findFirst({
      where: { id: saleId, establishmentId },
      include: { items: true, payments: true },
    });
    if (!sale) {
      throw new NotFoundException('Vente introuvable pour cet établissement');
    }
    return sale;
  }

  async listForDay(establishmentId: string, day: string) {
    const start = new Date(`${day}T00:00:00.000Z`);
    const end = new Date(`${day}T23:59:59.999Z`);
    return this.prisma.sale.findMany({
      where: { establishmentId, createdAt: { gte: start, lte: end } },
      include: { items: true, payments: true },
      orderBy: { createdAt: 'desc' },
    });
  }

  /** Restocks every item and reverses any credit granted — the sale itself is kept, only marked voided (audit trail). */
  async refund(establishmentId: string, userId: string, saleId: string) {
    const sale = await this.prisma.sale.findFirst({
      where: { id: saleId, establishmentId },
      include: { items: true, credits: true },
    });
    if (!sale) {
      throw new NotFoundException('Vente introuvable pour cet établissement');
    }
    if (sale.voidedAt) {
      throw new ConflictException('Cette vente a déjà été remboursée');
    }

    return this.prisma.$transaction(async (tx) => {
      for (const item of sale.items) {
        const quantity = item.quantity.toNumber();
        await tx.product.update({ where: { id: item.productId }, data: { stockQuantity: { increment: quantity } } });
        await tx.stockMovement.create({
          data: {
            productId: item.productId,
            type: 'in',
            quantity,
            reason: `Remboursement vente ${sale.id}`,
            createdBy: userId,
          },
        });
      }

      if (sale.customerId) {
        const creditAmount = sale.credits.reduce((sum, c) => sum + c.amount.toNumber(), 0);
        if (creditAmount > 0) {
          const customer = await tx.customer.findUniqueOrThrow({ where: { id: sale.customerId } });
          const nextBalance = Math.max(0, customer.creditBalance.toNumber() - creditAmount);
          await tx.customer.update({ where: { id: sale.customerId }, data: { creditBalance: nextBalance } });
        }
      }

      return tx.sale.update({ where: { id: saleId }, data: { voidedAt: new Date() }, include: { items: true, payments: true } });
    });
  }

  /**
   * Corrige la quantité d'une ligne d'une vente déjà enregistrée (ex. erreur
   * de saisie du caissier) — demande utilisateur du 2026-09-14, listing des
   * ventes accessible depuis Caisse/Addition (voir docs/api/pos.md).
   *
   * Le stock est ajusté par la **différence** (`delta`), jamais via un
   * mouvement `adjustment` : ce type fixe le stock à une valeur absolue
   * plutôt que de le corriger relativement (voir `stock-math.ts`), ce qui
   * écraserait tout mouvement survenu depuis la vente d'origine. `delta > 0`
   * (quantité augmentée) décrémente le stock restant comme une vente
   * normale (`out`, refusé si le stock ne suffit plus) ; `delta < 0`
   * restocke la différence (`in`), même logique que `refund` ci-dessus mais
   * partielle.
   *
   * `subtotal`/`total` sont incrémentés du même montant — préserve la remise
   * déjà appliquée (stockée comme un montant figé, pas une règle
   * recalculable) sans la toucher. Les paiements déjà enregistrés ne sont
   * jamais modifiés ici (voir `updatePaymentMethod`) : un écart entre le
   * nouveau total et la somme des paiements reste possible après une
   * correction de quantité, documenté plutôt que corrigé automatiquement —
   * l'utilisateur n'a demandé que deux corrections indépendantes (quantité
   * OU mode de paiement), jamais une réconciliation des montants.
   */
  async updateItemQuantity(establishmentId: string, userId: string, saleId: string, itemId: string, quantity: number) {
    const sale = await this.prisma.sale.findFirst({
      where: { id: saleId, establishmentId },
      include: { items: true },
    });
    if (!sale) {
      throw new NotFoundException('Vente introuvable pour cet établissement');
    }
    if (sale.voidedAt) {
      throw new ConflictException('Cette vente a déjà été remboursée');
    }
    const item = sale.items.find((i) => i.id === itemId);
    if (!item) {
      throw new NotFoundException('Article introuvable pour cette vente');
    }

    const oldQuantity = item.quantity.toNumber();
    const delta = quantity - oldQuantity;
    const totalDelta = delta * item.unitPrice.toNumber();

    return this.prisma.$transaction(async (tx) => {
      if (delta > 0) {
        const { count } = await tx.product.updateMany({
          where: { id: item.productId, stockQuantity: { gte: delta } },
          data: { stockQuantity: { decrement: delta } },
        });
        if (count === 0) {
          throw new ConflictException('Stock insuffisant pour cette correction');
        }
        await tx.stockMovement.create({
          data: { productId: item.productId, type: 'out', quantity: delta, reason: `Correction vente ${saleId}`, createdBy: userId },
        });
      } else if (delta < 0) {
        await tx.product.update({ where: { id: item.productId }, data: { stockQuantity: { increment: -delta } } });
        await tx.stockMovement.create({
          data: { productId: item.productId, type: 'in', quantity: -delta, reason: `Correction vente ${saleId}`, createdBy: userId },
        });
      }

      await tx.saleItem.update({ where: { id: itemId }, data: { quantity } });
      return tx.sale.update({
        where: { id: saleId },
        data: { subtotal: { increment: totalDelta }, total: { increment: totalDelta } },
        include: { items: true, payments: true },
      });
    });
  }

  /** Corrige le mode de paiement (Espèces/Mobile Money) d'une ligne déjà enregistrée — le montant ne change jamais ici, voir UpdateSalePaymentDto. */
  async updatePaymentMethod(establishmentId: string, saleId: string, paymentId: string, method: 'cash' | 'mobile_money') {
    const sale = await this.prisma.sale.findFirst({ where: { id: saleId, establishmentId } });
    if (!sale) {
      throw new NotFoundException('Vente introuvable pour cet établissement');
    }
    if (sale.voidedAt) {
      throw new ConflictException('Cette vente a déjà été remboursée');
    }
    const { count } = await this.prisma.payment.updateMany({ where: { id: paymentId, saleId }, data: { method } });
    if (count === 0) {
      throw new NotFoundException('Paiement introuvable pour cette vente');
    }
    return this.prisma.sale.findFirst({ where: { id: saleId }, include: { items: true, payments: true } });
  }
}
