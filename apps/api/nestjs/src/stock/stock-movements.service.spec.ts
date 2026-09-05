import { BadRequestException, NotFoundException } from '@nestjs/common';
import { Decimal } from '@prisma/client';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import { StockMovementsService } from './stock-movements.service.js';

function makePrismaMock() {
  return {
    product: { findFirst: vi.fn(), update: vi.fn(), findMany: vi.fn() },
    stockMovement: { create: vi.fn(), findMany: vi.fn(), findFirst: vi.fn() },
    $transaction: vi.fn(async (ops: unknown[]) => ops),
  };
}

describe('StockMovementsService', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: StockMovementsService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new StockMovementsService(prisma as unknown as PrismaService);
  });

  it('throws NotFoundException when the product does not belong to the establishment', async () => {
    prisma.product.findFirst.mockResolvedValue(null);
    await expect(
      service.create('est-1', 'prod-from-another-establishment', 'user-1', { type: 'in', quantity: 5 }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('rejects an "out" movement that would drive stock negative, without touching the database', async () => {
    prisma.product.findFirst.mockResolvedValue({ id: 'prod-1', stockQuantity: new Decimal(3) });
    await expect(service.create('est-1', 'prod-1', 'user-1', { type: 'out', quantity: 5 })).rejects.toBeInstanceOf(
      BadRequestException,
    );
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('applies a valid "in" movement: updates the product total and records the movement in one transaction', async () => {
    prisma.product.findFirst.mockResolvedValue({ id: 'prod-1', stockQuantity: new Decimal(10) });
    prisma.product.update.mockResolvedValue({});
    prisma.stockMovement.create.mockResolvedValue({ id: 'mvt-1' });

    await service.create('est-1', 'prod-1', 'user-1', { type: 'in', quantity: 5, reason: 'Réception' });

    expect(prisma.product.update).toHaveBeenCalledWith({ where: { id: 'prod-1' }, data: { stockQuantity: 15 } });
    expect(prisma.stockMovement.create).toHaveBeenCalledWith({
      data: { productId: 'prod-1', type: 'in', quantity: 5, reason: 'Réception', createdBy: 'user-1' },
    });
    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
  });

  it('replays an already-recorded movement idempotently, never touching the product again', async () => {
    const alreadyRecorded = { id: 'mvt-1', productId: 'prod-1', type: 'in', quantity: new Decimal(5) };
    prisma.stockMovement.findFirst.mockResolvedValue(alreadyRecorded);

    const result = await service.create('est-1', 'prod-1', 'user-1', { id: 'mvt-1', type: 'in', quantity: 5 });

    expect(result).toBe(alreadyRecorded);
    expect(prisma.product.findFirst).not.toHaveBeenCalled();
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('listLowStockAlerts filters out products at/under their threshold and ignores products with no threshold', async () => {
    prisma.product.findMany.mockResolvedValue([
      { id: 'p1', name: 'Bière', stockQuantity: new Decimal(2), minStock: new Decimal(5) }, // low
      { id: 'p2', name: 'Soda', stockQuantity: new Decimal(20), minStock: new Decimal(5) }, // fine
    ]);

    const alerts = await service.listLowStockAlerts('est-1');

    expect(prisma.product.findMany).toHaveBeenCalledWith({
      where: { establishmentId: 'est-1', status: 'active', minStock: { gt: 0 } },
      select: { id: true, name: true, stockQuantity: true, minStock: true },
    });
    expect(alerts).toEqual([{ id: 'p1', name: 'Bière', stockQuantity: 2, minStock: 5 }]);
  });
});
