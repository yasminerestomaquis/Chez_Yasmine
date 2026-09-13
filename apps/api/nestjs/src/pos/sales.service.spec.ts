import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { Decimal } from '@prisma/client';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import type { ActivityNotifierService } from '../notifications/activity-notifier.service.js';
import { SalesService } from './sales.service.js';

const activityNotifierMock = { notify: vi.fn() } as unknown as ActivityNotifierService;

function makePrismaMock() {
  const prisma: Record<string, unknown> = {
    product: {
      findMany: vi.fn(),
      update: vi.fn(),
      updateMany: vi.fn().mockResolvedValue({ count: 1 }),
      findUniqueOrThrow: vi.fn(),
    },
    stockMovement: { create: vi.fn() },
    sale: { create: vi.fn(), findFirst: vi.fn(), findMany: vi.fn(), update: vi.fn() },
    customer: { findFirst: vi.fn(), update: vi.fn(), findUniqueOrThrow: vi.fn() },
    credit: { create: vi.fn() },
    order: { findFirst: vi.fn(), update: vi.fn(), count: vi.fn() },
    restaurantTable: { update: vi.fn() },
    purchase: { findFirst: vi.fn() },
    expense: { findFirst: vi.fn() },
    $transaction: vi.fn(async (callback: (tx: unknown) => unknown) => callback(prisma)),
  };
  return prisma;
}

const product = (
  over: Partial<{ id: string; name: string; salePrice: number | null; stockQuantity: number }> = {},
) => ({
  id: over.id ?? 'p1',
  establishmentId: 'est-1',
  name: over.name ?? 'Bière 65cl',
  // salePrice: null simule une catégorie à prix variable (ex. Poulets,
  // Poissons, Plats africains) — voir docs/api/catalog.md.
  salePrice: over.salePrice === null ? null : new Decimal(over.salePrice ?? 1000),
  stockQuantity: new Decimal(over.stockQuantity ?? 20),
});

describe('SalesService.create', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: SalesService;

  beforeEach(() => {
    vi.mocked(activityNotifierMock.notify).mockClear();
    prisma = makePrismaMock();
    service = new SalesService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('replays an already-created sale idempotently, never touching products/stock again', async () => {
    const alreadyCreated = { id: 'sale-1', items: [], payments: [] };
    (prisma.sale as any).findFirst.mockResolvedValue(alreadyCreated);

    const result = await service.create('est-1', 'user-1', {
      id: 'sale-1',
      items: [{ productId: 'p1', quantity: 1 }],
      payments: [{ method: 'cash', amount: 1000 }],
    } as any);

    expect(result).toBe(alreadyCreated);
    expect(prisma.product.findMany).not.toHaveBeenCalled();
    expect(prisma.$transaction).not.toHaveBeenCalled();
    expect(activityNotifierMock.notify).not.toHaveBeenCalled();
  });

  it('rejects a product that does not belong to the establishment', async () => {
    (prisma.product as any).findMany.mockResolvedValue([]);
    await expect(
      service.create('est-1', 'user-1', {
        items: [{ productId: 'p1', quantity: 1 }],
        payments: [{ method: 'cash', amount: 1000 }],
      } as any),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a sale that would drive stock negative, before starting a transaction', async () => {
    (prisma.product as any).findMany.mockResolvedValue([product({ stockQuantity: 1 })]);
    await expect(
      service.create('est-1', 'user-1', {
        items: [{ productId: 'p1', quantity: 5 }],
        payments: [{ method: 'cash', amount: 5000 }],
      } as any),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('rejects a payment split that does not sum to the total', async () => {
    (prisma.product as any).findMany.mockResolvedValue([product()]);
    await expect(
      service.create('est-1', 'user-1', {
        items: [{ productId: 'p1', quantity: 2 }],
        payments: [{ method: 'cash', amount: 1000 }], // total should be 2000
      } as any),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a credit payment with no customer', async () => {
    (prisma.product as any).findMany.mockResolvedValue([product()]);
    await expect(
      service.create('est-1', 'user-1', {
        items: [{ productId: 'p1', quantity: 1 }],
        payments: [{ method: 'credit', amount: 1000 }],
      } as any),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('completes a valid cash sale: decrements stock, creates the sale, records a "sale" stock movement', async () => {
    (prisma.product as any).findMany.mockResolvedValue([product({ stockQuantity: 20 })]);
    (prisma.sale as any).create.mockResolvedValue({ id: 'sale-1', items: [], payments: [] });

    await service.create('est-1', 'user-1', {
      items: [{ productId: 'p1', quantity: 3 }],
      payments: [{ method: 'cash', amount: 3000 }],
    } as any);

    expect(prisma.product.updateMany).toHaveBeenCalledWith({
      where: { id: 'p1', stockQuantity: { gte: 3 } },
      data: { stockQuantity: { decrement: 3 } },
    });
    expect(prisma.stockMovement.create).toHaveBeenCalledWith({
      data: { productId: 'p1', type: 'sale', quantity: 3, createdBy: 'user-1' },
    });
    expect(prisma.sale.create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ subtotal: 3000, discount: 0, total: 3000 }) }),
    );
    expect(prisma.credit.create).not.toHaveBeenCalled();
    expect(activityNotifierMock.notify).toHaveBeenCalledWith('est-1', 'Nouvelle vente', expect.stringContaining('3'));
  });

  describe('two lines of the same product (variable-pricing sold at two different prices the same day)', () => {
    it('rejects the sale when the SUM of both lines exceeds stock, even though each line alone would fit', async () => {
      // Stock = 3 ; deux lignes de 2 (prix différents) : chacune isolément
      // tient (2 < 3), mais ensemble elles demandent 4 > 3.
      (prisma.product as any).findMany.mockResolvedValue([product({ stockQuantity: 3, salePrice: null })]);

      await expect(
        service.create('est-1', 'user-1', {
          items: [
            { productId: 'p1', quantity: 2, unitPrice: 1000 },
            { productId: 'p1', quantity: 2, unitPrice: 1200 },
          ],
          payments: [{ method: 'cash', amount: 4400 }],
        } as any),
      ).rejects.toBeInstanceOf(ConflictException);
      expect(prisma.$transaction).not.toHaveBeenCalled();
    });

    it('decrements stock by the aggregated quantity once, but still records one stock movement per line', async () => {
      (prisma.product as any).findMany.mockResolvedValue([product({ stockQuantity: 4, salePrice: null })]);
      (prisma.sale as any).create.mockResolvedValue({ id: 'sale-1', items: [], payments: [] });

      await service.create('est-1', 'user-1', {
        items: [
          { productId: 'p1', quantity: 2, unitPrice: 1000 },
          { productId: 'p1', quantity: 2, unitPrice: 1200 },
        ],
        payments: [{ method: 'cash', amount: 4400 }],
      } as any);

      expect(prisma.product.updateMany).toHaveBeenCalledTimes(1);
      expect(prisma.product.updateMany).toHaveBeenCalledWith({
        where: { id: 'p1', stockQuantity: { gte: 4 } },
        data: { stockQuantity: { decrement: 4 } },
      });
      expect(prisma.stockMovement.create).toHaveBeenCalledTimes(2);
    });
  });

  it('rejects the sale (rolling back the transaction) when a concurrent sale already consumed the stock the pre-check saw as sufficient', async () => {
    // Simule la course : le pré-contrôle (product.findMany) voit encore du
    // stock, mais la décrémentation conditionnelle dans la transaction
    // échoue (count: 0) parce qu'une autre vente l'a consommé entre-temps.
    (prisma.product as any).findMany.mockResolvedValue([product({ stockQuantity: 5 })]);
    (prisma.product as any).updateMany.mockResolvedValueOnce({ count: 0 });

    await expect(
      service.create('est-1', 'user-1', {
        items: [{ productId: 'p1', quantity: 3 }],
        payments: [{ method: 'cash', amount: 3000 }],
      } as any),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(prisma.sale.create).not.toHaveBeenCalled();
  });

  describe('variable-pricing products (ex. Poulets, Poissons, Plats africains)', () => {
    it('rejects the sale when the cashier did not enter a price', async () => {
      (prisma.product as any).findMany.mockResolvedValue([product({ salePrice: null })]);
      await expect(
        service.create('est-1', 'user-1', {
          items: [{ productId: 'p1', quantity: 1 }],
          payments: [{ method: 'cash', amount: 1500 }],
        } as any),
      ).rejects.toBeInstanceOf(BadRequestException);
      expect(prisma.$transaction).not.toHaveBeenCalled();
    });

    it('uses the cashier-entered unitPrice for totals and the recorded sale item', async () => {
      (prisma.product as any).findMany.mockResolvedValue([product({ salePrice: null })]);
      (prisma.sale as any).create.mockResolvedValue({ id: 'sale-1', items: [], payments: [] });

      await service.create('est-1', 'user-1', {
        items: [{ productId: 'p1', quantity: 2, unitPrice: 1500 }],
        payments: [{ method: 'cash', amount: 3000 }],
      } as any);

      expect(prisma.sale.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            total: 3000,
            items: { create: [expect.objectContaining({ productId: 'p1', quantity: 2, unitPrice: 1500 })] },
          }),
        }),
      );
    });

    it('ignores any client-sent unitPrice for a fixed-price product (server stays the source of truth)', async () => {
      (prisma.product as any).findMany.mockResolvedValue([product({ salePrice: 1000 })]);
      (prisma.sale as any).create.mockResolvedValue({ id: 'sale-1', items: [], payments: [] });

      await service.create('est-1', 'user-1', {
        items: [{ productId: 'p1', quantity: 1, unitPrice: 1 }], // tentative de prix cassé, ignorée
        payments: [{ method: 'cash', amount: 1000 }],
      } as any);

      expect(prisma.sale.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            items: { create: [expect.objectContaining({ unitPrice: 1000 })] },
          }),
        }),
      );
    });
  });

  it('rejects checking out an order that is already closed', async () => {
    (prisma.product as any).findMany.mockResolvedValue([product()]);
    (prisma.order as any).findFirst.mockResolvedValue({ id: 'order-1', status: 'closed', tableId: 't1' });

    await expect(
      service.create('est-1', 'user-1', {
        orderId: 'order-1',
        items: [{ productId: 'p1', quantity: 1 }],
        payments: [{ method: 'cash', amount: 1000 }],
      } as any),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('closes the order and frees its table when the sale checks out a table addition', async () => {
    (prisma.product as any).findMany.mockResolvedValue([product()]);
    (prisma.order as any).findFirst.mockResolvedValue({ id: 'order-1', status: 'open', tableId: 't1' });
    (prisma.order as any).count.mockResolvedValue(0);
    (prisma.sale as any).create.mockResolvedValue({ id: 'sale-1', items: [], payments: [] });

    await service.create('est-1', 'user-1', {
      orderId: 'order-1',
      items: [{ productId: 'p1', quantity: 1 }],
      payments: [{ method: 'cash', amount: 1000 }],
    } as any);

    expect(prisma.order.update).toHaveBeenCalledWith({
      where: { id: 'order-1' },
      data: { status: 'closed', closedAt: expect.any(Date) },
    });
    expect(prisma.restaurantTable.update).toHaveBeenCalledWith({ where: { id: 't1' }, data: { status: 'free' } });
  });

  it('closes the order but keeps the table occupied when another addition is still open on it', async () => {
    (prisma.product as any).findMany.mockResolvedValue([product()]);
    (prisma.order as any).findFirst.mockResolvedValue({ id: 'order-1', status: 'open', tableId: 't1' });
    (prisma.order as any).count.mockResolvedValue(1);
    (prisma.sale as any).create.mockResolvedValue({ id: 'sale-1', items: [], payments: [] });

    await service.create('est-1', 'user-1', {
      orderId: 'order-1',
      items: [{ productId: 'p1', quantity: 1 }],
      payments: [{ method: 'cash', amount: 1000 }],
    } as any);

    expect(prisma.order.update).toHaveBeenCalledWith({
      where: { id: 'order-1' },
      data: { status: 'closed', closedAt: expect.any(Date) },
    });
    expect(prisma.restaurantTable.update).not.toHaveBeenCalled();
  });

  it('rejects a credit sale that would exceed the customer credit limit, before starting a transaction', async () => {
    (prisma.product as any).findMany.mockResolvedValue([product({ salePrice: 5000 })]);
    (prisma.customer as any).findFirst.mockResolvedValue({
      id: 'cust-1',
      creditBalance: new Decimal(4000),
      creditLimit: new Decimal(5000),
    });

    await expect(
      service.create('est-1', 'user-1', {
        customerId: 'cust-1',
        items: [{ productId: 'p1', quantity: 1 }],
        payments: [{ method: 'credit', amount: 5000 }],
      } as any),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('records a credit sale: increases the customer balance and creates a Credit row', async () => {
    (prisma.product as any).findMany.mockResolvedValue([product({ salePrice: 2000 })]);
    (prisma.customer as any).findFirst.mockResolvedValue({
      id: 'cust-1',
      creditBalance: new Decimal(0),
      creditLimit: new Decimal(10000),
    });
    (prisma.sale as any).create.mockResolvedValue({ id: 'sale-1', items: [], payments: [] });

    await service.create('est-1', 'user-1', {
      customerId: 'cust-1',
      items: [{ productId: 'p1', quantity: 1 }],
      payments: [{ method: 'credit', amount: 2000 }],
    } as any);

    expect(prisma.customer.update).toHaveBeenCalledWith({ where: { id: 'cust-1' }, data: { creditBalance: 2000 } });
    expect(prisma.credit.create).toHaveBeenCalledWith({ data: { customerId: 'cust-1', saleId: 'sale-1', amount: 2000 } });
  });

  it('passes through orderNumber/marketNumber to the sale record', async () => {
    (prisma.product as any).findMany.mockResolvedValue([product()]);
    (prisma.sale as any).create.mockResolvedValue({ id: 'sale-1', items: [], payments: [] });

    await service.create('est-1', 'user-1', {
      items: [{ productId: 'p1', quantity: 1 }],
      payments: [{ method: 'cash', amount: 1000 }],
      orderNumber: 3,
      marketNumber: 7,
    } as any);

    expect(prisma.sale.create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ orderNumber: 3, marketNumber: 7 }) }),
    );
  });
});

describe('SalesService.lastOrderNumber / lastMarketNumber', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: SalesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new SalesService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('returns null when no purchase exists yet', async () => {
    (prisma.purchase as any).findFirst.mockResolvedValue(null);
    await expect(service.lastOrderNumber('est-1')).resolves.toBeNull();
    expect(prisma.purchase.findFirst).toHaveBeenCalledWith({
      where: { establishmentId: 'est-1' },
      orderBy: { orderNumber: 'desc' },
      select: { orderNumber: true },
    });
  });

  it('returns the highest purchase order number, not the most recently created row', async () => {
    // Même motif que PurchasesService.nextOrderNumber : une commande peut
    // être saisie après coup, donc trier par date de création pourrait
    // suggérer un numéro déjà dépassé — c'est le tri par `orderNumber`
    // lui-même qui compte, pas `createdAt`.
    (prisma.purchase as any).findFirst.mockResolvedValue({ orderNumber: 5 });
    await expect(service.lastOrderNumber('est-1')).resolves.toBe(5);
  });

  it('returns null when no "Marché" expense exists yet', async () => {
    (prisma.expense as any).findFirst.mockResolvedValue(null);
    await expect(service.lastMarketNumber('est-1')).resolves.toBeNull();
    expect(prisma.expense.findFirst).toHaveBeenCalledWith({
      where: { establishmentId: 'est-1', category: 'Marché', marketNumber: { not: null } },
      orderBy: { marketNumber: 'desc' },
      select: { marketNumber: true },
    });
  });

  it('returns the highest market number, not the most recently created row', async () => {
    (prisma.expense as any).findFirst.mockResolvedValue({ marketNumber: 9 });
    await expect(service.lastMarketNumber('est-1')).resolves.toBe(9);
  });
});

describe('SalesService.refund', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: SalesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new SalesService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('throws NotFoundException for a sale outside the establishment', async () => {
    (prisma.sale as any).findFirst.mockResolvedValue(null);
    await expect(service.refund('est-1', 'user-1', 'sale-x')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('rejects refunding an already-voided sale', async () => {
    (prisma.sale as any).findFirst.mockResolvedValue({ id: 'sale-1', voidedAt: new Date(), items: [], credits: [] });
    await expect(service.refund('est-1', 'user-1', 'sale-1')).rejects.toBeInstanceOf(ConflictException);
  });

  it('restocks every item and marks the sale voided', async () => {
    (prisma.sale as any).findFirst.mockResolvedValue({
      id: 'sale-1',
      customerId: null,
      voidedAt: null,
      items: [{ productId: 'p1', quantity: new Decimal(2) }],
      credits: [],
    });
    (prisma.sale as any).update.mockResolvedValue({ id: 'sale-1', voidedAt: new Date() });

    await service.refund('est-1', 'user-1', 'sale-1');

    expect(prisma.product.update).toHaveBeenCalledWith({ where: { id: 'p1' }, data: { stockQuantity: { increment: 2 } } });
    expect(prisma.stockMovement.create).toHaveBeenCalledWith({
      data: { productId: 'p1', type: 'in', quantity: 2, reason: 'Remboursement vente sale-1', createdBy: 'user-1' },
    });
    expect(prisma.sale.update).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 'sale-1' }, data: { voidedAt: expect.any(Date) } }),
    );
  });

  it('reverses the credit balance for a refunded credit sale', async () => {
    (prisma.sale as any).findFirst.mockResolvedValue({
      id: 'sale-1',
      customerId: 'cust-1',
      voidedAt: null,
      items: [],
      credits: [{ amount: new Decimal(2000) }],
    });
    (prisma.customer as any).findUniqueOrThrow.mockResolvedValue({ id: 'cust-1', creditBalance: new Decimal(5000) });
    (prisma.sale as any).update.mockResolvedValue({ id: 'sale-1' });

    await service.refund('est-1', 'user-1', 'sale-1');

    expect(prisma.customer.update).toHaveBeenCalledWith({ where: { id: 'cust-1' }, data: { creditBalance: 3000 } });
  });
});
