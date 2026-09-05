import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { Decimal } from '@prisma/client';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import { PurchasesService } from './purchases.service.js';

function makePrismaMock() {
  const prisma: Record<string, unknown> = {
    supplier: { findFirst: vi.fn() },
    product: { findMany: vi.fn(), update: vi.fn() },
    purchase: { create: vi.fn(), findFirst: vi.fn(), findMany: vi.fn(), update: vi.fn() },
    stockMovement: { create: vi.fn() },
    $transaction: vi.fn(async (callback: (tx: unknown) => unknown) => callback(prisma)),
  };
  return prisma;
}

describe('PurchasesService.create', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: PurchasesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new PurchasesService(prisma as unknown as PrismaService);
  });

  it('rejects a supplier from another establishment', async () => {
    (prisma.supplier as any).findFirst.mockResolvedValue(null);
    await expect(
      service.create('est-1', { supplierId: 'sup-x', items: [{ productId: 'p1', quantity: 1, unitPrice: 500 }] }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a product from another establishment', async () => {
    (prisma.product as any).findMany.mockResolvedValue([]);
    await expect(
      service.create('est-1', { items: [{ productId: 'p1', quantity: 1, unitPrice: 500 }] }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('computes the total from quantity * unitPrice across all lines, and does not touch stock yet', async () => {
    (prisma.product as any).findMany.mockResolvedValue([{ id: 'p1' }, { id: 'p2' }]);
    (prisma.purchase as any).create.mockResolvedValue({ id: 'purchase-1' });

    await service.create('est-1', {
      items: [
        { productId: 'p1', quantity: 10, unitPrice: 500 },
        { productId: 'p2', quantity: 2, unitPrice: 1000 },
      ],
    });

    expect(prisma.purchase.create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ status: 'pending', total: 7000 }) }),
    );
    expect(prisma.product.update).not.toHaveBeenCalled();
    expect(prisma.stockMovement.create).not.toHaveBeenCalled();
  });
});

describe('PurchasesService.receive', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: PurchasesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new PurchasesService(prisma as unknown as PrismaService);
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
    (prisma.purchase as any).update.mockResolvedValue({ id: 'purchase-1', status: 'received' });

    await service.receive('est-1', 'purchase-1', 'user-1');

    expect(prisma.product.update).toHaveBeenCalledWith({ where: { id: 'p1' }, data: { stockQuantity: { increment: 10 } } });
    expect(prisma.product.update).toHaveBeenCalledWith({ where: { id: 'p2' }, data: { stockQuantity: { increment: 5 } } });
    expect(prisma.stockMovement.create).toHaveBeenCalledWith({
      data: { productId: 'p1', type: 'in', quantity: 10, reason: 'Réception achat purchase-1', createdBy: 'user-1' },
    });
    expect(prisma.purchase.update).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 'purchase-1' }, data: { status: 'received' } }),
    );
  });
});

describe('PurchasesService.cancel', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: PurchasesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new PurchasesService(prisma as unknown as PrismaService);
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
