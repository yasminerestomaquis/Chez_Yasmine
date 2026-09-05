import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { Decimal } from '@prisma/client';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import { SalesService } from './sales.service.js';

function makePrismaMock() {
  const prisma: Record<string, unknown> = {
    product: { findMany: vi.fn(), update: vi.fn(), findUniqueOrThrow: vi.fn() },
    stockMovement: { create: vi.fn() },
    sale: { create: vi.fn(), findFirst: vi.fn(), findMany: vi.fn(), update: vi.fn() },
    customer: { findFirst: vi.fn(), update: vi.fn(), findUniqueOrThrow: vi.fn() },
    credit: { create: vi.fn() },
    order: { findFirst: vi.fn(), update: vi.fn() },
    restaurantTable: { update: vi.fn() },
    $transaction: vi.fn(async (callback: (tx: unknown) => unknown) => callback(prisma)),
  };
  return prisma;
}

const product = (over: Partial<{ id: string; name: string; salePrice: number; stockQuantity: number }> = {}) => ({
  id: over.id ?? 'p1',
  establishmentId: 'est-1',
  name: over.name ?? 'Bière 65cl',
  salePrice: new Decimal(over.salePrice ?? 1000),
  stockQuantity: new Decimal(over.stockQuantity ?? 20),
});

describe('SalesService.create', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: SalesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new SalesService(prisma as unknown as PrismaService);
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

    expect(prisma.product.update).toHaveBeenCalledWith({ where: { id: 'p1' }, data: { stockQuantity: { decrement: 3 } } });
    expect(prisma.stockMovement.create).toHaveBeenCalledWith({
      data: { productId: 'p1', type: 'sale', quantity: 3, createdBy: 'user-1' },
    });
    expect(prisma.sale.create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ subtotal: 3000, discount: 0, total: 3000 }) }),
    );
    expect(prisma.credit.create).not.toHaveBeenCalled();
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
});

describe('SalesService.refund', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: SalesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new SalesService(prisma as unknown as PrismaService);
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
