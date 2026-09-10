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

    for (const item of dto.items) {
      const product = productById.get(item.productId)!;
      if (product.stockQuantity.toNumber() < item.quantity) {
        throw new ConflictException(`Stock insuffisant pour ${product.name}`);
      }
    }

    // Un produit à prix fixe ignore tout unitPrice envoyé par le client (le
    // serveur reste seul juge du prix) ; un produit à prix variable (aucun
    // salePrice en catalogue) exige que le caissier l'ait saisi en caisse.
    const unitPriceByItemIndex = dto.items.map((item) => {
      const product = productById.get(item.productId)!;
      if (product.salePrice != null) return product.salePrice.toNumber();
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
      for (const item of dto.items) {
        await tx.product.update({ where: { id: item.productId }, data: { stockQuantity: { decrement: item.quantity } } });
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
          await tx.restaurantTable.update({ where: { id: orderToClose.tableId }, data: { status: 'free' } });
        }
      }

      return sale;
    });
    await this.activityNotifier.notify(establishmentId, 'Nouvelle vente', `${totals.total.toLocaleString('fr-FR')} FCFA`);
    return sale;
  }

  /** Suggestion éditable pour la caisse : N° de la dernière commande d'achat enregistrée (toutes catégories/fournisseurs confondus), ou null s'il n'y en a aucune. Jamais imposé côté serveur. */
  async lastOrderNumber(establishmentId: string): Promise<number | null> {
    const last = await this.prisma.purchase.findFirst({
      where: { establishmentId },
      orderBy: { createdAt: 'desc' },
      select: { orderNumber: true },
    });
    return last?.orderNumber ?? null;
  }

  /** Même principe pour le dernier N° de marché (dépense « Marché ») enregistré. */
  async lastMarketNumber(establishmentId: string): Promise<number | null> {
    const last = await this.prisma.expense.findFirst({
      where: { establishmentId, category: 'Marché' },
      orderBy: { createdAt: 'desc' },
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
}
