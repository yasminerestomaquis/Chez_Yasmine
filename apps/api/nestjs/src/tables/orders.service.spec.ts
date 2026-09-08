import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { Decimal } from '@prisma/client';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import { OrdersService } from './orders.service.js';

function makePrismaMock() {
  const prisma: Record<string, unknown> = {
    order: { create: vi.fn(), findFirst: vi.fn(), update: vi.fn(), findUniqueOrThrow: vi.fn() },
    restaurantTable: { findFirst: vi.fn(), update: vi.fn() },
    product: { findFirst: vi.fn() },
    orderItem: { create: vi.fn(), deleteMany: vi.fn(), findMany: vi.fn(), updateMany: vi.fn() },
    $transaction: vi.fn(async (callback: (tx: unknown) => unknown) => callback(prisma)),
  };
  return prisma;
}

describe('OrdersService.openTable', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: OrdersService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new OrdersService(prisma as unknown as PrismaService);
  });

  it('throws NotFoundException for a table outside the establishment', async () => {
    (prisma.restaurantTable as any).findFirst.mockResolvedValue(null);
    await expect(service.openTable('est-1', 'table-x', 'user-1')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('rejects opening an already-occupied table', async () => {
    (prisma.restaurantTable as any).findFirst.mockResolvedValue({ id: 't1', status: 'occupied' });
    await expect(service.openTable('est-1', 't1', 'user-1')).rejects.toBeInstanceOf(ConflictException);
  });

  it('creates an open order and occupies the table', async () => {
    (prisma.restaurantTable as any).findFirst.mockResolvedValue({ id: 't1', status: 'free' });
    (prisma.order as any).create.mockResolvedValue({ id: 'order-1' });

    await service.openTable('est-1', 't1', 'user-1');

    expect(prisma.order.create).toHaveBeenCalledWith({
      data: { establishmentId: 'est-1', tableId: 't1', serverId: 'user-1', status: 'open' },
    });
    expect(prisma.restaurantTable.update).toHaveBeenCalledWith({ where: { id: 't1' }, data: { status: 'occupied' } });
  });
});

describe('OrdersService.addItem', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: OrdersService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new OrdersService(prisma as unknown as PrismaService);
  });

  it('rejects adding an item to a closed order', async () => {
    (prisma.order as any).findFirst.mockResolvedValue({ id: 'order-1', status: 'closed' });
    await expect(service.addItem('est-1', 'order-1', { productId: 'p1', quantity: 1 })).rejects.toBeInstanceOf(
      ConflictException,
    );
  });

  it('rejects a product from another establishment', async () => {
    (prisma.order as any).findFirst.mockResolvedValue({ id: 'order-1', status: 'open' });
    (prisma.product as any).findFirst.mockResolvedValue(null);
    await expect(service.addItem('est-1', 'order-1', { productId: 'p1', quantity: 1 })).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it("uses the product's current sale price, never a client-supplied one", async () => {
    (prisma.order as any).findFirst.mockResolvedValue({ id: 'order-1', status: 'open' });
    (prisma.product as any).findFirst.mockResolvedValue({ id: 'p1', salePrice: new Decimal(1500) });

    await service.addItem('est-1', 'order-1', { productId: 'p1', quantity: 2 });

    expect(prisma.orderItem.create).toHaveBeenCalledWith({
      data: { orderId: 'order-1', productId: 'p1', quantity: 2, unitPrice: new Decimal(1500) },
    });
  });

  it('rejects a variable-pricing product (ex. Poulets, Poissons, Plats africains) — no price entry here yet', async () => {
    (prisma.order as any).findFirst.mockResolvedValue({ id: 'order-1', status: 'open' });
    (prisma.product as any).findFirst.mockResolvedValue({ id: 'p1', name: 'Poulet braisé', salePrice: null });

    await expect(service.addItem('est-1', 'order-1', { productId: 'p1', quantity: 1 })).rejects.toBeInstanceOf(
      BadRequestException,
    );
    expect(prisma.orderItem.create).not.toHaveBeenCalled();
  });
});

describe('OrdersService.transfer', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: OrdersService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new OrdersService(prisma as unknown as PrismaService);
  });

  it('rejects transferring to the same table', async () => {
    (prisma.order as any).findFirst.mockResolvedValue({ id: 'order-1', status: 'open', tableId: 't1' });
    await expect(service.transfer('est-1', 'order-1', { toTableId: 't1' })).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects transferring to an occupied table', async () => {
    (prisma.order as any).findFirst.mockResolvedValue({ id: 'order-1', status: 'open', tableId: 't1' });
    (prisma.restaurantTable as any).findFirst.mockResolvedValue({ id: 't2', status: 'occupied' });
    await expect(service.transfer('est-1', 'order-1', { toTableId: 't2' })).rejects.toBeInstanceOf(ConflictException);
  });

  it('moves the order, occupies the new table, and frees the old one', async () => {
    (prisma.order as any).findFirst.mockResolvedValue({ id: 'order-1', status: 'open', tableId: 't1' });
    (prisma.restaurantTable as any).findFirst.mockResolvedValue({ id: 't2', status: 'free' });
    (prisma.order as any).update.mockResolvedValue({ id: 'order-1', tableId: 't2' });

    await service.transfer('est-1', 'order-1', { toTableId: 't2' });

    expect(prisma.order.update).toHaveBeenCalledWith({ where: { id: 'order-1' }, data: { tableId: 't2' } });
    expect(prisma.restaurantTable.update).toHaveBeenCalledWith({ where: { id: 't2' }, data: { status: 'occupied' } });
    expect(prisma.restaurantTable.update).toHaveBeenCalledWith({ where: { id: 't1' }, data: { status: 'free' } });
  });
});

describe('OrdersService.merge', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: OrdersService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new OrdersService(prisma as unknown as PrismaService);
  });

  it('rejects merging an order into itself', async () => {
    await expect(service.merge('est-1', 'order-1', 'order-1')).rejects.toBeInstanceOf(BadRequestException);
  });

  it('moves every item, closes the source order, and frees its table', async () => {
    (prisma.order as any).findFirst
      .mockResolvedValueOnce({ id: 'order-1', status: 'open', tableId: 't1' })
      .mockResolvedValueOnce({ id: 'order-2', status: 'open', tableId: 't2' });
    (prisma.order as any).findUniqueOrThrow.mockResolvedValue({ id: 'order-2', items: [] });

    await service.merge('est-1', 'order-1', 'order-2');

    expect(prisma.orderItem.updateMany).toHaveBeenCalledWith({ where: { orderId: 'order-1' }, data: { orderId: 'order-2' } });
    expect(prisma.order.update).toHaveBeenCalledWith({
      where: { id: 'order-1' },
      data: { status: 'closed', closedAt: expect.any(Date) },
    });
    expect(prisma.restaurantTable.update).toHaveBeenCalledWith({ where: { id: 't1' }, data: { status: 'free' } });
  });
});

describe('OrdersService.split', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: OrdersService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new OrdersService(prisma as unknown as PrismaService);
  });

  it('rejects splitting off items that do not belong to the order', async () => {
    (prisma.order as any).findFirst.mockResolvedValue({ id: 'order-1', status: 'open', tableId: 't1', serverId: 'u1' });
    (prisma.orderItem as any).findMany.mockResolvedValue([]); // asked for 1 item, found 0
    await expect(service.split('est-1', 'order-1', { itemIds: ['item-x'], toTableId: 't1' })).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('keeps the table occupied (not freed) when splitting onto the same table', async () => {
    (prisma.order as any).findFirst.mockResolvedValue({ id: 'order-1', status: 'open', tableId: 't1', serverId: 'u1' });
    (prisma.orderItem as any).findMany.mockResolvedValue([{ id: 'item-1' }]);
    (prisma.order as any).create.mockResolvedValue({ id: 'order-2' });
    (prisma.order as any).findUniqueOrThrow.mockResolvedValue({ id: 'order-2', items: [] });

    await service.split('est-1', 'order-1', { itemIds: ['item-1'], toTableId: 't1' });

    expect(prisma.order.create).toHaveBeenCalledWith({
      data: { establishmentId: 'est-1', tableId: 't1', serverId: 'u1', status: 'open' },
    });
    expect(prisma.restaurantTable.update).not.toHaveBeenCalled();
  });

  it('requires the destination table to be free when splitting onto a different table', async () => {
    (prisma.order as any).findFirst.mockResolvedValue({ id: 'order-1', status: 'open', tableId: 't1', serverId: 'u1' });
    (prisma.orderItem as any).findMany.mockResolvedValue([{ id: 'item-1' }]);
    (prisma.restaurantTable as any).findFirst.mockResolvedValue({ id: 't2', status: 'occupied' });

    await expect(service.split('est-1', 'order-1', { itemIds: ['item-1'], toTableId: 't2' })).rejects.toBeInstanceOf(
      ConflictException,
    );
  });
});
