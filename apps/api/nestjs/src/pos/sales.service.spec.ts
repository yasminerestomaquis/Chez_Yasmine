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
    saleItem: { update: vi.fn() },
    payment: { updateMany: vi.fn() },
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
  over: Partial<{
    id: string;
    name: string;
    salePrice: number | null;
    unitSalePrice: number | null;
    referenceSalePrice: number | null;
    stockQuantity: number;
  }> = {},
) => ({
  id: over.id ?? 'p1',
  establishmentId: 'est-1',
  name: over.name ?? 'Bière 65cl',
  // salePrice: null simule une catégorie à prix variable (ex. Poulets,
  // Poissons, Plats africains) — voir docs/api/catalog.md.
  salePrice: over.salePrice === null ? null : new Decimal(over.salePrice ?? 1000),
  // unitSalePrice: prix de vente alternatif à l'unité (ex. Heineken 33/Despé
  // 33, normalement vendues par lot de 3) — voir SaleItemDto.sellAsUnit.
  unitSalePrice: over.unitSalePrice == null ? null : new Decimal(over.unitSalePrice),
  // referenceSalePrice : prix de référence variable (ex. Gbêlê, 3000 FCFA/L)
  // — voir SaleItemDto.amountPaid.
  referenceSalePrice: over.referenceSalePrice == null ? null : new Decimal(over.referenceSalePrice),
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
    expect(activityNotifierMock.notify).toHaveBeenCalledWith(
      'est-1',
      'user-1',
      'Nouvelle vente',
      `Bière 65cl — ${(3000).toLocaleString('fr-FR')} FCFA`,
    );
  });

  it('notifies with every distinct product name sold, deduplicated (2026-09-14)', async () => {
    (prisma.product as any).findMany.mockResolvedValue([
      product({ id: 'p1', name: 'Heineken 33', stockQuantity: 20 }),
      product({ id: 'p2', name: 'Poulet Braisé', stockQuantity: 20 }),
    ]);
    (prisma.sale as any).create.mockResolvedValue({ id: 'sale-1', items: [], payments: [] });

    await service.create('est-1', 'user-1', {
      items: [
        { productId: 'p1', quantity: 2 },
        { productId: 'p1', quantity: 1 }, // même produit, deuxième ligne — ne doit apparaître qu'une fois
        { productId: 'p2', quantity: 1 },
      ],
      payments: [{ method: 'cash', amount: 4000 }],
    } as any);

    expect(activityNotifierMock.notify).toHaveBeenCalledWith(
      'est-1',
      'user-1',
      'Nouvelle vente',
      expect.stringContaining('Heineken 33, Poulet Braisé'),
    );
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

  describe('prix de référence variable (ex. Gbêlê, 3000 FCFA/L) — decision utilisateur du 2026-09-24', () => {
    it('deduit quantite et prix unitaire du montant paye', async () => {
      (prisma.product as any).findMany.mockResolvedValue([product({ salePrice: null, referenceSalePrice: 3000, stockQuantity: 40 })]);
      (prisma.sale as any).create.mockResolvedValue({ id: 'sale-1', items: [], payments: [] });

      await service.create('est-1', 'user-1', {
        items: [{ productId: 'p1', amountPaid: 100 }],
        payments: [{ method: 'cash', amount: 100 }],
      } as any);

      const created = (prisma.sale.create as any).mock.calls[0][0].data.items.create[0];
      expect(created.quantity).toBe(0.03);
      expect(created.quantity * created.unitPrice).toBeCloseTo(100, 6);
      expect((prisma.stockMovement.create as any).mock.calls[0][0].data.quantity).toBe(0.03);
    });

    it('refuse la vente sans montant paye', async () => {
      (prisma.product as any).findMany.mockResolvedValue([product({ salePrice: null, referenceSalePrice: 3000 })]);
      await expect(
        service.create('est-1', 'user-1', {
          items: [{ productId: 'p1' }],
          payments: [{ method: 'cash', amount: 100 }],
        } as any),
      ).rejects.toBeInstanceOf(BadRequestException);
      expect(prisma.$transaction).not.toHaveBeenCalled();
    });

    it('accepte lencaissement dune addition, qui rejoue quantite/unitPrice deja resolus (checkout)', async () => {
      (prisma.product as any).findMany.mockResolvedValue([product({ salePrice: null, referenceSalePrice: 3000, stockQuantity: 40 })]);
      (prisma.sale as any).create.mockResolvedValue({ id: 'sale-1', items: [], payments: [] });

      await service.create('est-1', 'user-1', {
        items: [{ productId: 'p1', quantity: 0.03, unitPrice: 3333.33 }],
        payments: [{ method: 'cash', amount: 100 }],
      } as any);

      const created = (prisma.sale.create as any).mock.calls[0][0].data.items.create[0];
      expect(created.quantity).toBe(0.03);
      expect(created.unitPrice).toBe(3333.33);
    });
  });

  describe('sellAsUnit (ex. Heineken 33/Despé 33, vendues par lot de 3 à 2 000 FCFA ou à l\'unité à 700 FCFA)', () => {
    it('uses unitSalePrice when sellAsUnit is true and the product has one', async () => {
      (prisma.product as any).findMany.mockResolvedValue([product({ salePrice: 2000, unitSalePrice: 700 })]);
      (prisma.sale as any).create.mockResolvedValue({ id: 'sale-1', items: [], payments: [] });

      await service.create('est-1', 'user-1', {
        items: [{ productId: 'p1', quantity: 1, sellAsUnit: true }],
        payments: [{ method: 'cash', amount: 700 }],
      } as any);

      expect(prisma.sale.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            total: 700,
            items: { create: [expect.objectContaining({ unitPrice: 700 })] },
          }),
        }),
      );
    });

    it('uses the normal salePrice when sellAsUnit is absent, even if the product has a unitSalePrice', async () => {
      (prisma.product as any).findMany.mockResolvedValue([product({ salePrice: 2000, unitSalePrice: 700 })]);
      (prisma.sale as any).create.mockResolvedValue({ id: 'sale-1', items: [], payments: [] });

      await service.create('est-1', 'user-1', {
        items: [{ productId: 'p1', quantity: 1 }],
        payments: [{ method: 'cash', amount: 2000 }],
      } as any);

      expect(prisma.sale.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            items: { create: [expect.objectContaining({ unitPrice: 2000 })] },
          }),
        }),
      );
    });

    it('ignores sellAsUnit when the product has no unitSalePrice configured (falls back to salePrice)', async () => {
      (prisma.product as any).findMany.mockResolvedValue([product({ salePrice: 1000, unitSalePrice: null })]);
      (prisma.sale as any).create.mockResolvedValue({ id: 'sale-1', items: [], payments: [] });

      await service.create('est-1', 'user-1', {
        items: [{ productId: 'p1', quantity: 1, sellAsUnit: true }],
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

describe('SalesService.updateItemQuantity', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: SalesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new SalesService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('throws NotFoundException for a sale outside the establishment', async () => {
    (prisma.sale as any).findFirst.mockResolvedValue(null);
    await expect(service.updateItemQuantity('est-1', 'user-1', 'sale-x', 'item-1', 5)).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('rejects correcting an already-voided sale', async () => {
    (prisma.sale as any).findFirst.mockResolvedValue({ id: 'sale-1', voidedAt: new Date(), items: [] });
    await expect(service.updateItemQuantity('est-1', 'user-1', 'sale-1', 'item-1', 5)).rejects.toBeInstanceOf(
      ConflictException,
    );
  });

  it('throws NotFoundException for an item that does not belong to the sale', async () => {
    (prisma.sale as any).findFirst.mockResolvedValue({ id: 'sale-1', voidedAt: null, items: [] });
    await expect(service.updateItemQuantity('est-1', 'user-1', 'sale-1', 'item-x', 5)).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('increasing the quantity decrements the additional stock (type "out") and increases subtotal/total', async () => {
    (prisma.sale as any).findFirst.mockResolvedValue({
      id: 'sale-1',
      voidedAt: null,
      items: [{ id: 'item-1', productId: 'p1', quantity: new Decimal(2), unitPrice: new Decimal(1000) }],
    });
    (prisma.sale as any).update.mockResolvedValue({ id: 'sale-1' });

    await service.updateItemQuantity('est-1', 'user-1', 'sale-1', 'item-1', 5);

    expect(prisma.product.updateMany).toHaveBeenCalledWith({
      where: { id: 'p1', stockQuantity: { gte: 3 } },
      data: { stockQuantity: { decrement: 3 } },
    });
    expect(prisma.stockMovement.create).toHaveBeenCalledWith({
      data: { productId: 'p1', type: 'out', quantity: 3, reason: 'Correction vente sale-1', createdBy: 'user-1' },
    });
    expect(prisma.saleItem.update).toHaveBeenCalledWith({ where: { id: 'item-1' }, data: { quantity: 5 } });
    expect(prisma.sale.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'sale-1' },
        data: { subtotal: { increment: 3000 }, total: { increment: 3000 } },
      }),
    );
  });

  it('decreasing the quantity restocks the difference (type "in") and decreases subtotal/total', async () => {
    (prisma.sale as any).findFirst.mockResolvedValue({
      id: 'sale-1',
      voidedAt: null,
      items: [{ id: 'item-1', productId: 'p1', quantity: new Decimal(5), unitPrice: new Decimal(1000) }],
    });
    (prisma.sale as any).update.mockResolvedValue({ id: 'sale-1' });

    await service.updateItemQuantity('est-1', 'user-1', 'sale-1', 'item-1', 2);

    expect(prisma.product.update).toHaveBeenCalledWith({ where: { id: 'p1' }, data: { stockQuantity: { increment: 3 } } });
    expect(prisma.stockMovement.create).toHaveBeenCalledWith({
      data: { productId: 'p1', type: 'in', quantity: 3, reason: 'Correction vente sale-1', createdBy: 'user-1' },
    });
    expect(prisma.sale.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: { subtotal: { increment: -3000 }, total: { increment: -3000 } } }),
    );
  });

  it('rejects an increase the stock can no longer cover (concurrent depletion) and never touches the sale', async () => {
    (prisma.sale as any).findFirst.mockResolvedValue({
      id: 'sale-1',
      voidedAt: null,
      items: [{ id: 'item-1', productId: 'p1', quantity: new Decimal(2), unitPrice: new Decimal(1000) }],
    });
    (prisma.product as any).updateMany.mockResolvedValueOnce({ count: 0 });

    await expect(service.updateItemQuantity('est-1', 'user-1', 'sale-1', 'item-1', 5)).rejects.toBeInstanceOf(
      ConflictException,
    );
    expect(prisma.saleItem.update).not.toHaveBeenCalled();
    expect(prisma.sale.update).not.toHaveBeenCalled();
  });

  it('leaves stock and the transaction untouched when the quantity is unchanged', async () => {
    (prisma.sale as any).findFirst.mockResolvedValue({
      id: 'sale-1',
      voidedAt: null,
      items: [{ id: 'item-1', productId: 'p1', quantity: new Decimal(3), unitPrice: new Decimal(1000) }],
    });
    (prisma.sale as any).update.mockResolvedValue({ id: 'sale-1' });

    await service.updateItemQuantity('est-1', 'user-1', 'sale-1', 'item-1', 3);

    expect(prisma.product.updateMany).not.toHaveBeenCalled();
    expect(prisma.product.update).not.toHaveBeenCalled();
    expect(prisma.stockMovement.create).not.toHaveBeenCalled();
  });
});

describe('SalesService.updatePaymentMethod', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: SalesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new SalesService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('throws NotFoundException for a sale outside the establishment', async () => {
    (prisma.sale as any).findFirst.mockResolvedValue(null);
    await expect(service.updatePaymentMethod('est-1', 'sale-x', 'pay-1', 'mobile_money')).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('rejects correcting an already-voided sale', async () => {
    (prisma.sale as any).findFirst.mockResolvedValue({ id: 'sale-1', voidedAt: new Date() });
    await expect(service.updatePaymentMethod('est-1', 'sale-1', 'pay-1', 'mobile_money')).rejects.toBeInstanceOf(
      ConflictException,
    );
  });

  it('throws NotFoundException for a payment that does not belong to the sale', async () => {
    (prisma.sale as any).findFirst.mockResolvedValue({ id: 'sale-1', voidedAt: null });
    (prisma.payment as any).updateMany.mockResolvedValue({ count: 0 });
    await expect(service.updatePaymentMethod('est-1', 'sale-1', 'pay-x', 'mobile_money')).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('updates the method, leaving the amount untouched', async () => {
    (prisma.sale as any).findFirst
      .mockResolvedValueOnce({ id: 'sale-1', voidedAt: null })
      .mockResolvedValueOnce({ id: 'sale-1', payments: [{ id: 'pay-1', method: 'mobile_money', amount: 1000 }] });
    (prisma.payment as any).updateMany.mockResolvedValue({ count: 1 });

    const result = await service.updatePaymentMethod('est-1', 'sale-1', 'pay-1', 'mobile_money');

    expect(prisma.payment.updateMany).toHaveBeenCalledWith({
      where: { id: 'pay-1', saleId: 'sale-1' },
      data: { method: 'mobile_money' },
    });
    expect(result).toEqual({ id: 'sale-1', payments: [{ id: 'pay-1', method: 'mobile_money', amount: 1000 }] });
  });
});
