import { BadRequestException, NotFoundException } from '@nestjs/common';
import { Decimal } from '@prisma/client';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import { LossesService } from './losses.service.js';

function makePrismaMock() {
  const prisma: Record<string, unknown> = {
    loss: { findFirst: vi.fn(), findMany: vi.fn(), create: vi.fn() },
    product: { findFirst: vi.fn(), update: vi.fn() },
    stockMovement: { create: vi.fn() },
    $transaction: vi.fn(async (callback: (tx: unknown) => unknown) => callback(prisma)),
  };
  return prisma;
}

describe('LossesService.create', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: LossesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new LossesService(prisma as unknown as PrismaService);
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
    (prisma.product as any).findFirst.mockResolvedValue({ id: 'p1', stockQuantity: new Decimal(10) });
    (prisma.loss as any).create.mockResolvedValue({ id: 'loss-1', productId: 'p1', quantity: 4 });

    await service.create('est-1', 'user-1', { id: 'loss-1', productId: 'p1', quantity: 4, reason: 'Casse' });

    expect(prisma.product.update).toHaveBeenCalledWith({ where: { id: 'p1' }, data: { stockQuantity: 6 } });
    expect(prisma.stockMovement.create).toHaveBeenCalledWith({
      data: { productId: 'p1', type: 'loss', quantity: 4, reason: 'Casse', createdBy: 'user-1' },
    });
    expect(prisma.loss.create).toHaveBeenCalledWith({
      data: { id: 'loss-1', establishmentId: 'est-1', productId: 'p1', quantity: 4, reason: 'Casse', createdBy: 'user-1' },
    });
  });
});

describe('LossesService.list', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: LossesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new LossesService(prisma as unknown as PrismaService);
  });

  it('computes estimatedValue from quantity * purchasePrice, defaulting to 0 when purchasePrice is unset', async () => {
    (prisma.loss as any).findMany.mockResolvedValue([
      {
        id: 'loss-1',
        productId: 'p1',
        quantity: new Decimal(3),
        reason: 'Casse',
        createdAt: new Date('2026-09-01'),
        product: { name: 'Bière', purchasePrice: new Decimal(400) },
      },
      {
        id: 'loss-2',
        productId: 'p2',
        quantity: new Decimal(2),
        reason: null,
        createdAt: new Date('2026-09-02'),
        product: { name: 'Glaçons', purchasePrice: null },
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
        estimatedValue: 1200,
        createdAt: new Date('2026-09-01'),
      },
      {
        id: 'loss-2',
        productId: 'p2',
        productName: 'Glaçons',
        quantity: 2,
        reason: null,
        estimatedValue: 0,
        createdAt: new Date('2026-09-02'),
      },
    ]);
  });
});
