import { BadRequestException, NotFoundException } from '@nestjs/common';
import { Decimal } from '@prisma/client';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import type { ActivityNotifierService } from '../notifications/activity-notifier.service.js';
import { LossesService } from './losses.service.js';

const activityNotifierMock = { notify: vi.fn() } as unknown as ActivityNotifierService;

function makePrismaMock() {
  const prisma: Record<string, unknown> = {
    loss: { findFirst: vi.fn(), findMany: vi.fn(), create: vi.fn(), update: vi.fn(), delete: vi.fn() },
    product: { findFirst: vi.fn(), update: vi.fn() },
    stockMovement: { create: vi.fn(), findFirst: vi.fn(), update: vi.fn(), delete: vi.fn() },
    $transaction: vi.fn(async (callback: (tx: unknown) => unknown) => callback(prisma)),
  };
  return prisma;
}

describe('LossesService.create', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: LossesService;

  beforeEach(() => {
    vi.mocked(activityNotifierMock.notify).mockClear();
    prisma = makePrismaMock();
    service = new LossesService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('returns the existing loss unchanged on idempotent replay, without touching stock', async () => {
    (prisma.loss as any).findFirst.mockResolvedValue({ id: 'loss-1' });

    const result = await service.create('est-1', 'user-1', { id: 'loss-1', productId: 'p1', quantity: 2 });

    expect(result).toEqual({ id: 'loss-1' });
    expect(prisma.product.findFirst).not.toHaveBeenCalled();
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('throws NotFoundException for a product outside the establishment', async () => {
    (prisma.product as any).findFirst.mockResolvedValue(null);
    await expect(service.create('est-1', 'user-1', { productId: 'p-x', quantity: 1 })).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('rejects a loss larger than the current stock, before any write', async () => {
    (prisma.product as any).findFirst.mockResolvedValue({ id: 'p1', stockQuantity: new Decimal(3) });
    await expect(service.create('est-1', 'user-1', { productId: 'p1', quantity: 10 })).rejects.toBeInstanceOf(
      BadRequestException,
    );
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('decrements stock, writes a loss stock movement, and records the Loss row in one transaction', async () => {
    (prisma.product as any).findFirst.mockResolvedValue({ id: 'p1', name: 'Poulet Braisé', stockQuantity: new Decimal(10) });
    (prisma.loss as any).create.mockResolvedValue({ id: 'loss-1', productId: 'p1', quantity: 4 });

    await service.create('est-1', 'user-1', { id: 'loss-1', productId: 'p1', quantity: 4, reason: 'Casse' });

    expect(prisma.product.update).toHaveBeenCalledWith({ where: { id: 'p1' }, data: { stockQuantity: 6 } });
    expect(prisma.stockMovement.create).toHaveBeenCalledWith({
      data: { productId: 'p1', type: 'loss', quantity: 4, reason: 'Casse', createdBy: 'user-1' },
    });
    expect(prisma.loss.create).toHaveBeenCalledWith({
      data: { id: 'loss-1', establishmentId: 'est-1', productId: 'p1', quantity: 4, reason: 'Casse', createdBy: 'user-1' },
    });
    expect(activityNotifierMock.notify).toHaveBeenCalledWith(
      'est-1',
      'user-1',
      'Perte enregistrée',
      expect.stringContaining('Poulet Braisé'),
    );
  });

  it('does not notify on idempotent replay of an already-recorded loss', async () => {
    (prisma.loss as any).findFirst.mockResolvedValue({ id: 'loss-1' });
    await service.create('est-1', 'user-1', { id: 'loss-1', productId: 'p1', quantity: 2 });
    expect(activityNotifierMock.notify).not.toHaveBeenCalled();
  });
});

describe('LossesService.list', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: LossesService;

  beforeEach(() => {
    vi.mocked(activityNotifierMock.notify).mockClear();
    prisma = makePrismaMock();
    service = new LossesService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('computes estimatedValue from quantity * SALE price, falling back to the reference sale price, then 0 (2026-09-20)', async () => {
    (prisma.loss as any).findMany.mockResolvedValue([
      {
        id: 'loss-1',
        productId: 'p1',
        quantity: new Decimal(3),
        reason: 'Casse',
        createdAt: new Date('2026-09-01'),
        product: { name: 'Bière', salePrice: new Decimal(500), referenceSalePrice: null },
        createdByUser: { fullName: 'Awa Koné' },
      },
      {
        id: 'loss-2',
        productId: 'p2',
        quantity: new Decimal(2),
        reason: null,
        createdAt: new Date('2026-09-02'),
        product: { name: 'Gbêlê', salePrice: null, referenceSalePrice: new Decimal(4000) },
        createdByUser: null,
      },
    ]);

    const result = await service.list('est-1');

    expect(result).toEqual([
      {
        id: 'loss-1',
        productId: 'p1',
        productName: 'Bière',
        quantity: 3,
        reason: 'Casse',
        unitSalePrice: 500,
        estimatedValue: 1500,
        createdByName: 'Awa Koné',
        createdAt: new Date('2026-09-01'),
      },
      {
        id: 'loss-2',
        productId: 'p2',
        productName: 'Gbêlê',
        quantity: 2,
        reason: null,
        unitSalePrice: 4000,
        estimatedValue: 8000,
        createdByName: null,
        createdAt: new Date('2026-09-02'),
      },
    ]);
  });
});

const D = (n: number) => new Decimal(n);
const existingLoss = {
  id: 'loss-1',
  productId: 'p1',
  quantity: D(4),
  reason: 'Casse',
  createdBy: 'user-1',
  createdAt: new Date('2026-09-10T10:00:00Z'),
};

describe('LossesService.update / remove (2026-09-20)', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: LossesService;

  beforeEach(() => {
    vi.mocked(activityNotifierMock.notify).mockClear();
    prisma = makePrismaMock();
    service = new LossesService(prisma as unknown as PrismaService, activityNotifierMock);
    (prisma.loss as any).findFirst.mockResolvedValue(existingLoss);
    (prisma.stockMovement as any).findFirst.mockResolvedValue({ id: 'mv-1' });
  });

  it('throws NotFoundException for an unknown loss', async () => {
    (prisma.loss as any).findFirst.mockResolvedValue(null);
    await expect(service.update('est-1', 'u', 'x', { quantity: 1 })).rejects.toBeInstanceOf(NotFoundException);
    await expect(service.remove('est-1', 'u', 'x')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('same product: gives the old quantity back before applying the new one', async () => {
    // stock 6 (déjà -4) ; nouvelle quantité 5 -> 6 + 4 - 5 = 5
    (prisma.product as any).findFirst.mockResolvedValue({ id: 'p1', name: 'Poulet', stockQuantity: D(6) });

    await service.update('est-1', 'user-2', 'loss-1', { quantity: 5, reason: 'Périmé', createdAt: '2026-09-12T08:00:00Z' });

    expect(prisma.product.update).toHaveBeenCalledWith({ where: { id: 'p1' }, data: { stockQuantity: 5 } });
    expect(prisma.stockMovement.update).toHaveBeenCalledWith({
      where: { id: 'mv-1' },
      data: { productId: 'p1', quantity: 5, reason: 'Périmé', createdAt: new Date('2026-09-12T08:00:00Z') },
    });
    expect(prisma.loss.update).toHaveBeenCalledWith({
      where: { id: 'loss-1' },
      data: { productId: 'p1', quantity: 5, reason: 'Périmé', createdAt: new Date('2026-09-12T08:00:00Z') },
    });
    expect(activityNotifierMock.notify).toHaveBeenCalledWith('est-1', 'user-2', 'Perte modifiée', expect.any(String));
  });

  it('same product: refuses a new quantity larger than the restored stock', async () => {
    (prisma.product as any).findFirst.mockResolvedValue({ id: 'p1', name: 'Poulet', stockQuantity: D(1) });

    await expect(service.update('est-1', 'u', 'loss-1', { quantity: 9 })).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('different product: restores the old product and decrements the new one', async () => {
    (prisma.product as any).findFirst.mockImplementation(async ({ where }: { where: { id: string } }) =>
      where.id === 'p2'
        ? { id: 'p2', name: 'Bière', stockQuantity: D(10) }
        : { id: 'p1', name: 'Poulet', stockQuantity: D(6) },
    );

    await service.update('est-1', 'u', 'loss-1', { productId: 'p2' });

    expect(prisma.product.update).toHaveBeenCalledWith({ where: { id: 'p1' }, data: { stockQuantity: 10 } });
    expect(prisma.product.update).toHaveBeenCalledWith({ where: { id: 'p2' }, data: { stockQuantity: 6 } });
    expect(prisma.stockMovement.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ productId: 'p2', quantity: 4 }) }),
    );
  });

  it('creates the loss movement when none can be found (legacy data)', async () => {
    (prisma.stockMovement as any).findFirst.mockResolvedValue(null);
    (prisma.product as any).findFirst.mockResolvedValue({ id: 'p1', name: 'Poulet', stockQuantity: D(6) });

    await service.update('est-1', 'u', 'loss-1', { quantity: 2 });

    expect(prisma.stockMovement.update).not.toHaveBeenCalled();
    expect(prisma.stockMovement.create).toHaveBeenCalled();
  });

  it('remove: returns the quantity to stock and deletes the movement and the loss', async () => {
    (prisma.product as any).findFirst.mockResolvedValue({ id: 'p1', name: 'Poulet', stockQuantity: D(6) });

    await service.remove('est-1', 'user-3', 'loss-1');

    expect(prisma.product.update).toHaveBeenCalledWith({ where: { id: 'p1' }, data: { stockQuantity: 10 } });
    expect(prisma.stockMovement.delete).toHaveBeenCalledWith({ where: { id: 'mv-1' } });
    expect(prisma.loss.delete).toHaveBeenCalledWith({ where: { id: 'loss-1' } });
    expect(activityNotifierMock.notify).toHaveBeenCalledWith('est-1', 'user-3', 'Perte supprimée', expect.any(String));
  });
});

describe('LossesService.create — date saisie (2026-09-20)', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: LossesService;

  beforeEach(() => {
    vi.mocked(activityNotifierMock.notify).mockClear();
    prisma = makePrismaMock();
    service = new LossesService(prisma as unknown as PrismaService, activityNotifierMock);
    (prisma.product as any).findFirst.mockResolvedValue({ id: 'p1', name: 'Poulet', stockQuantity: new Decimal(10) });
    (prisma.loss as any).create.mockResolvedValue({ id: 'loss-1' });
  });

  it('applique la date fournie à la perte ET à son mouvement de stock', async () => {
    await service.create('est-1', 'user-1', { productId: 'p1', quantity: 2, createdAt: '2026-09-10T08:00:00Z' });

    const date = new Date('2026-09-10T08:00:00Z');
    expect(prisma.stockMovement.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ createdAt: date }),
    });
    expect(prisma.loss.create).toHaveBeenCalledWith({ data: expect.objectContaining({ createdAt: date }) });
  });

  it('laisse le horodatage serveur quand aucune date est fournie', async () => {
    await service.create('est-1', 'user-1', { productId: 'p1', quantity: 2 });

    expect(prisma.loss.create).toHaveBeenCalledWith({ data: expect.objectContaining({ createdAt: undefined }) });
  });

  it('refuse une date dans le futur', async () => {
    const future = new Date(Date.now() + 3 * 24 * 3600 * 1000).toISOString();

    await expect(service.create('est-1', 'user-1', { productId: 'p1', quantity: 2, createdAt: future })).rejects.toBeInstanceOf(
      BadRequestException,
    );
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });
});
