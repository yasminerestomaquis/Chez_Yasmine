import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { Decimal } from '@prisma/client';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import type { ActivityNotifierService } from '../notifications/activity-notifier.service.js';
import { PurchasesService } from './purchases.service.js';

const activityNotifierMock = { notify: vi.fn() } as unknown as ActivityNotifierService;

function makePrismaMock() {
  const prisma: Record<string, unknown> = {
    supplier: { findFirst: vi.fn() },
    product: { findMany: vi.fn(), update: vi.fn(), findUniqueOrThrow: vi.fn() },
    purchase: {
      create: vi.fn(),
      findFirst: vi.fn(),
      findMany: vi.fn(),
      update: vi.fn(),
      findUniqueOrThrow: vi.fn(),
      delete: vi.fn(),
    },
    purchaseItem: { deleteMany: vi.fn() },
    stockMovement: { create: vi.fn() },
    $transaction: vi.fn(async (callback: (tx: unknown) => unknown) => callback(prisma)),
  };
  return prisma;
}

/** Produit d'une catégorie à prix par casier, correctement renseigné (le cas nominal du nouveau flux Achats). */
const caseProduct = (over: Partial<{ id: string; name: string; bottlesPerCase: number; purchasePricePerCase: number }> = {}) => ({
  id: over.id ?? 'p1',
  establishmentId: 'est-1',
  name: over.name ?? 'Bière 65cl',
  bottlesPerCase: over.bottlesPerCase ?? 12,
  purchasePricePerCase: new Decimal(over.purchasePricePerCase ?? 19500),
  stockQuantity: new Decimal(20),
  category: { hasCasePricing: true },
});

/** Produit d'une catégorie à prix variable (Poulets, Poissons, Plats africains). */
const variableProduct = (over: Partial<{ id: string; name: string }> = {}) => ({
  id: over.id ?? 'p2',
  establishmentId: 'est-1',
  name: over.name ?? 'Poulet',
  bottlesPerCase: null,
  purchasePricePerCase: null,
  stockQuantity: new Decimal(0),
  category: { hasCasePricing: false, hasVariablePricing: true },
});

describe('PurchasesService.create', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: PurchasesService;

  beforeEach(() => {
    vi.mocked(activityNotifierMock.notify).mockClear();
    prisma = makePrismaMock();
    service = new PurchasesService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('rejects a supplier from another establishment', async () => {
    (prisma.supplier as any).findFirst.mockResolvedValue(null);
    await expect(
      service.create('est-1', 'user-1', { supplierId: 'sup-x', orderNumber: 1, items: [{ productId: 'p1', casesOrdered: 1 }] }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a product from another establishment', async () => {
    (prisma.product as any).findMany.mockResolvedValue([]);
    await expect(
      service.create('est-1', 'user-1', { orderNumber: 1, items: [{ productId: 'p1', casesOrdered: 1 }] }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a product whose category is not a case-pricing one', async () => {
    (prisma.product as any).findMany.mockResolvedValue([{ ...caseProduct(), category: { hasCasePricing: false } }]);
    await expect(
      service.create('est-1', 'user-1', { orderNumber: 1, items: [{ productId: 'p1', casesOrdered: 1 }] }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a product missing bottlesPerCase or purchasePricePerCase in the Catalogue', async () => {
    (prisma.product as any).findMany.mockResolvedValue([{ ...caseProduct(), bottlesPerCase: null }]);
    await expect(
      service.create('est-1', 'user-1', { orderNumber: 1, items: [{ productId: 'p1', casesOrdered: 1 }] }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('computes quantity/unitPrice from casesOrdered × bottlesPerCase, ignoring any client-sent price', async () => {
    (prisma.product as any).findMany.mockResolvedValue([caseProduct({ bottlesPerCase: 12, purchasePricePerCase: 19500 })]);
    (prisma.purchase as any).create.mockResolvedValue({ id: 'purchase-1', supplier: null, items: [] });

    await service.create('est-1', 'user-1', {
      orderNumber: 3,
      items: [{ productId: 'p1', casesOrdered: 2 }],
    });

    expect(prisma.purchase.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          orderNumber: 3,
          status: 'received',
          total: 39000, // 2 casiers × 19500
          items: {
            create: [
              expect.objectContaining({
                productId: 'p1',
                quantity: 24, // 2 casiers × 12 bouteilles
                unitPrice: 1625, // 19500 / 12
                casesOrdered: 2,
                bottlesPerCase: 12,
                purchasePricePerCase: 19500,
              }),
            ],
          },
        }),
      }),
    );
  });

  it('rejects a variable-pricing line missing quantityOrdered', async () => {
    (prisma.product as any).findMany.mockResolvedValue([variableProduct()]);
    await expect(
      service.create('est-1', 'user-1', { orderNumber: 1, items: [{ productId: 'p2', unitPurchasePrice: 3500 }] }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a variable-pricing line missing unitPurchasePrice', async () => {
    (prisma.product as any).findMany.mockResolvedValue([variableProduct()]);
    await expect(
      service.create('est-1', 'user-1', { orderNumber: 1, items: [{ productId: 'p2', quantityOrdered: 20 }] }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('computes a variable-pricing line directly from quantityOrdered/unitPurchasePrice, and snapshots Product.purchasePrice', async () => {
    (prisma.product as any).findMany.mockResolvedValue([variableProduct()]);
    (prisma.purchase as any).create.mockResolvedValue({ id: 'purchase-1', supplier: null, items: [] });

    await service.create('est-1', 'user-1', {
      orderNumber: 4,
      items: [{ productId: 'p2', quantityOrdered: 20, unitPurchasePrice: 3500 }],
    });

    expect(prisma.purchase.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          total: 70000, // 20 × 3500
          items: {
            create: [
              expect.objectContaining({
                productId: 'p2',
                quantity: 20,
                unitPrice: 3500,
                casesOrdered: null,
                bottlesPerCase: null,
                purchasePricePerCase: null,
              }),
            ],
          },
        }),
      }),
    );
    expect(prisma.product.update).toHaveBeenCalledWith({
      where: { id: 'p2' },
      data: { stockQuantity: { increment: 20 }, purchasePrice: 3500 },
    });
  });

  it('rejects a product whose category is neither case-pricing nor variable-pricing', async () => {
    (prisma.product as any).findMany.mockResolvedValue([{ ...variableProduct(), category: { hasCasePricing: false, hasVariablePricing: false } }]);
    await expect(
      service.create('est-1', 'user-1', { orderNumber: 1, items: [{ productId: 'p2', quantityOrdered: 1, unitPurchasePrice: 1 }] }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('increments stock immediately (no separate reception step) and notifies', async () => {
    (prisma.product as any).findMany.mockResolvedValue([caseProduct()]);
    (prisma.purchase as any).create.mockResolvedValue({
      id: 'purchase-1',
      supplier: { name: 'Brasseries du Sud' },
      items: [],
    });

    await service.create('est-1', 'user-1', { orderNumber: 1, items: [{ productId: 'p1', casesOrdered: 2 }] });

    expect(prisma.product.update).toHaveBeenCalledWith({ where: { id: 'p1' }, data: { stockQuantity: { increment: 24 } } });
    expect(prisma.stockMovement.create).toHaveBeenCalledWith({
      data: { productId: 'p1', type: 'in', quantity: 24, reason: 'Commande n°1', createdBy: 'user-1' },
    });
    expect(activityNotifierMock.notify).toHaveBeenCalledWith('est-1', 'Achat reçu', expect.stringContaining('Brasseries du Sud'));
  });
});

describe('PurchasesService.update', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: PurchasesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new PurchasesService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('throws NotFoundException for a purchase outside the establishment', async () => {
    (prisma.purchase as any).findFirst.mockResolvedValue(null);
    await expect(
      service.update('est-1', 'user-1', 'purchase-x', { orderNumber: 1, items: [{ productId: 'p1', casesOrdered: 1 }] }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('reverses the old lines and applies the new ones, net of the difference', async () => {
    (prisma.purchase as any).findFirst.mockResolvedValue({
      id: 'purchase-1',
      orderNumber: 5,
      items: [{ productId: 'p1', quantity: new Decimal(24) }],
    });
    (prisma.product as any).findUniqueOrThrow.mockResolvedValue({ id: 'p1', stockQuantity: new Decimal(30) });
    (prisma.product as any).findMany.mockResolvedValue([caseProduct({ bottlesPerCase: 12, purchasePricePerCase: 19500 })]);
    (prisma.purchase as any).findUniqueOrThrow.mockResolvedValue({ id: 'purchase-1' });

    await service.update('est-1', 'user-1', 'purchase-1', { items: [{ productId: 'p1', casesOrdered: 1 }] });

    // Reversal: 30 - 24 = 6, then re-application: 6 → +12 (via increment)
    expect(prisma.product.update).toHaveBeenCalledWith({ where: { id: 'p1' }, data: { stockQuantity: 6 } });
    expect(prisma.product.update).toHaveBeenCalledWith({ where: { id: 'p1' }, data: { stockQuantity: { increment: 12 } } });
    expect(prisma.purchaseItem.deleteMany).toHaveBeenCalledWith({ where: { purchaseId: 'purchase-1' } });
  });
});

describe('PurchasesService.remove', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: PurchasesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new PurchasesService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('throws NotFoundException for a purchase outside the establishment', async () => {
    (prisma.purchase as any).findFirst.mockResolvedValue(null);
    await expect(service.remove('est-1', 'user-1', 'purchase-x')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('clamps the stock reversal at 0 instead of going negative, then deletes the purchase', async () => {
    (prisma.purchase as any).findFirst.mockResolvedValue({
      id: 'purchase-1',
      orderNumber: 2,
      items: [{ productId: 'p1', quantity: new Decimal(24) }],
    });
    (prisma.product as any).findUniqueOrThrow.mockResolvedValue({ id: 'p1', stockQuantity: new Decimal(10) }); // déjà partiellement vendu

    await service.remove('est-1', 'user-1', 'purchase-1');

    expect(prisma.product.update).toHaveBeenCalledWith({ where: { id: 'p1' }, data: { stockQuantity: 0 } });
    expect(prisma.stockMovement.create).toHaveBeenCalledWith({
      data: { productId: 'p1', type: 'out', quantity: 24, reason: 'Suppression commande n°2', createdBy: 'user-1' },
    });
    expect(prisma.purchase.delete).toHaveBeenCalledWith({ where: { id: 'purchase-1' } });
  });
});

describe('PurchasesService.nextOrderNumber', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: PurchasesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new PurchasesService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('returns 1 when the supplier has no prior order', async () => {
    (prisma.purchase as any).findFirst.mockResolvedValue(null);
    await expect(service.nextOrderNumber('est-1', 'sup-1')).resolves.toBe(1);
    expect(prisma.purchase.findFirst).toHaveBeenCalledWith({
      where: { establishmentId: 'est-1', supplierId: 'sup-1' },
      orderBy: { orderNumber: 'desc' },
      select: { orderNumber: true },
    });
  });

  it('returns last + 1, scoped to that supplier', async () => {
    (prisma.purchase as any).findFirst.mockResolvedValue({ orderNumber: 7 });
    await expect(service.nextOrderNumber('est-1', 'sup-1')).resolves.toBe(8);
  });

  it('scopes to "no supplier" (null) when none is given', async () => {
    (prisma.purchase as any).findFirst.mockResolvedValue(null);
    await service.nextOrderNumber('est-1');
    expect(prisma.purchase.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({ where: { establishmentId: 'est-1', supplierId: null } }),
    );
  });
});

describe('PurchasesService.receive (flux hérité, commandes `pending` existantes)', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: PurchasesService;

  beforeEach(() => {
    vi.mocked(activityNotifierMock.notify).mockClear();
    prisma = makePrismaMock();
    service = new PurchasesService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('throws NotFoundException for a purchase outside the establishment', async () => {
    (prisma.purchase as any).findFirst.mockResolvedValue(null);
    await expect(service.receive('est-1', 'purchase-x', 'user-1')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('rejects receiving a purchase that is not pending', async () => {
    (prisma.purchase as any).findFirst.mockResolvedValue({ id: 'purchase-1', status: 'received', items: [] });
    await expect(service.receive('est-1', 'purchase-1', 'user-1')).rejects.toBeInstanceOf(ConflictException);
  });

  it('increments stock for every line, records an "in" movement per line, and marks the purchase received', async () => {
    (prisma.purchase as any).findFirst.mockResolvedValue({
      id: 'purchase-1',
      status: 'pending',
      items: [
        { productId: 'p1', quantity: new Decimal(10) },
        { productId: 'p2', quantity: new Decimal(5) },
      ],
    });
    (prisma.purchase as any).update.mockResolvedValue({
      id: 'purchase-1',
      status: 'received',
      total: new Decimal(1000),
      items: [{ productId: 'p1' }, { productId: 'p2' }],
      supplier: { name: 'Brasseries du Sud' },
    });

    await service.receive('est-1', 'purchase-1', 'user-1');

    expect(prisma.product.update).toHaveBeenCalledWith({ where: { id: 'p1' }, data: { stockQuantity: { increment: 10 } } });
    expect(prisma.product.update).toHaveBeenCalledWith({ where: { id: 'p2' }, data: { stockQuantity: { increment: 5 } } });
    expect(prisma.stockMovement.create).toHaveBeenCalledWith({
      data: { productId: 'p1', type: 'in', quantity: 10, reason: 'Réception achat purchase-1', createdBy: 'user-1' },
    });
    expect(prisma.purchase.update).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 'purchase-1' }, data: { status: 'received' } }),
    );
    expect(activityNotifierMock.notify).toHaveBeenCalledWith(
      'est-1',
      'Achat reçu',
      expect.stringContaining('Brasseries du Sud'),
    );
  });
});

describe('PurchasesService.cancel (flux hérité)', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: PurchasesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new PurchasesService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('rejects cancelling a purchase that has already been received', async () => {
    (prisma.purchase as any).findFirst.mockResolvedValue({ id: 'purchase-1', status: 'received' });
    await expect(service.cancel('est-1', 'purchase-1')).rejects.toBeInstanceOf(ConflictException);
    expect(prisma.purchase.update).not.toHaveBeenCalled();
  });

  it('cancels a pending purchase without touching stock', async () => {
    (prisma.purchase as any).findFirst.mockResolvedValue({ id: 'purchase-1', status: 'pending' });
    (prisma.purchase as any).update.mockResolvedValue({ id: 'purchase-1', status: 'cancelled' });

    await service.cancel('est-1', 'purchase-1');

    expect(prisma.purchase.update).toHaveBeenCalledWith({ where: { id: 'purchase-1' }, data: { status: 'cancelled' } });
    expect(prisma.stockMovement.create).not.toHaveBeenCalled();
  });
});
