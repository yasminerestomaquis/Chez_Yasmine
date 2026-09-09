import { Decimal } from '@prisma/client';
import { describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import { ChartsService } from './charts.service.js';

function makePrismaMock() {
  return {
    saleItem: { findMany: vi.fn() },
    product: { findFirst: vi.fn() },
    stockMovement: { findMany: vi.fn() },
    expense: { findMany: vi.fn() },
  };
}

function expense(overrides: { createdAt?: Date; amount?: number; category?: string | null } = {}) {
  return {
    expenseDate: overrides.createdAt ?? new Date('2026-09-07T10:00:00Z'),
    amount: new Decimal(overrides.amount ?? 1000),
    category: overrides.category === undefined ? 'Eau' : overrides.category,
  };
}

interface ItemOverrides {
  createdAt?: Date;
  quantity?: number;
  unitPrice?: number;
  purchasePrice?: number;
  productId?: string;
  name?: string;
  categoryId?: string | null;
  categoryName?: string;
  hasCasePricing?: boolean;
  bottlesPerCase?: number | null;
  purchasePricePerCase?: number | null;
}

function item(overrides: ItemOverrides = {}) {
  const categoryId = overrides.categoryId === undefined ? 'c1' : overrides.categoryId;
  return {
    quantity: new Decimal(overrides.quantity ?? 1),
    unitPrice: new Decimal(overrides.unitPrice ?? 100),
    productId: overrides.productId ?? 'p1',
    name: overrides.name ?? 'Produit',
    sale: { createdAt: overrides.createdAt ?? new Date('2026-09-07T10:00:00Z') },
    product: {
      purchasePrice: new Decimal(overrides.purchasePrice ?? 60),
      bottlesPerCase: overrides.bottlesPerCase ?? null,
      purchasePricePerCase: overrides.purchasePricePerCase != null ? new Decimal(overrides.purchasePricePerCase) : null,
      categoryId,
      category:
        categoryId === null
          ? null
          : { name: overrides.categoryName ?? 'Boissons', hasCasePricing: overrides.hasCasePricing ?? false },
    },
  };
}

describe('ChartsService.weeklyTotal', () => {
  it('buckets revenue by weekday (Monday-first) for the week containing weekStart', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.saleItem.findMany.mockResolvedValue([
      item({ createdAt: new Date('2026-09-07T10:00:00Z'), quantity: 2, unitPrice: 500 }), // Lundi
      item({ createdAt: new Date('2026-09-09T10:00:00Z'), quantity: 1, unitPrice: 300 }), // Mercredi
    ]);

    const result = await service.weeklyTotal('est-1', 'revenue', '2026-09-07');

    expect(result.weekStart).toBe('2026-09-07');
    expect(result.weekEnd).toBe('2026-09-13');
    expect(result.series).toHaveLength(1);
    expect(result.series[0].points[0]).toEqual({ day: 'Lundi', value: 1000 });
    expect(result.series[0].points[1]).toEqual({ day: 'Mardi', value: 0 });
    expect(result.series[0].points[2]).toEqual({ day: 'Mercredi', value: 300 });
  });

  it('snaps any weekday given as weekStart back to that week\'s Monday', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.saleItem.findMany.mockResolvedValue([]);

    const result = await service.weeklyTotal('est-1', 'revenue', '2026-09-10'); // un jeudi

    expect(result.weekStart).toBe('2026-09-07');
    expect(result.weekEnd).toBe('2026-09-13');
  });

  it('computes profit as revenue minus quantity times the current purchase price', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.saleItem.findMany.mockResolvedValue([item({ quantity: 2, unitPrice: 500, purchasePrice: 300 })]);

    const result = await service.weeklyTotal('est-1', 'profit', '2026-09-07');

    expect(result.series[0].points[0].value).toBe(400); // (500 - 300) * 2
  });

  it('uses purchasePricePerCase/bottlesPerCase for profit in a case-pricing category, not purchasePrice', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.saleItem.findMany.mockResolvedValue([
      item({
        quantity: 2,
        unitPrice: 3000,
        purchasePrice: 2500, // ne doit pas être utilisé
        hasCasePricing: true,
        bottlesPerCase: 12,
        purchasePricePerCase: 19500,
      }),
    ]);

    const result = await service.weeklyTotal('est-1', 'profit', '2026-09-07');

    expect(result.series[0].points[0].value).toBeCloseTo(2 * (3000 - 19500 / 12)); // pas 2 * (3000 - 2500)
  });

  it('excludes sales outside the requested week', async () => {
    const prisma = makePrismaMock();
    prisma.saleItem.findMany.mockResolvedValue([]);
    const service = new ChartsService(prisma as unknown as PrismaService);
    await service.weeklyTotal('est-1', 'revenue', '2026-09-07');

    expect(prisma.saleItem.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          sale: expect.objectContaining({
            establishmentId: 'est-1',
            voidedAt: null,
            createdAt: { gte: new Date('2026-09-07T00:00:00'), lte: new Date('2026-09-13T23:59:59.999') },
          }),
        }),
      }),
    );
  });
});

describe('ChartsService.weeklyByCategory', () => {
  it('groups by category sorted by weekly total descending when unfiltered', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.saleItem.findMany.mockResolvedValue([
      item({ categoryId: 'c1', categoryName: 'Boissons', quantity: 1, unitPrice: 100 }),
      item({ categoryId: 'c2', categoryName: 'Plats', quantity: 1, unitPrice: 500 }),
      item({ categoryId: null, quantity: 1, unitPrice: 50 }),
    ]);

    const result = await service.weeklyByCategory('est-1', 'revenue', '2026-09-07');

    expect(result.series.map((s) => s.name)).toEqual(['Plats', 'Boissons', 'Sans catégorie']);
  });

  it('filters to a single category when categoryId is given', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.saleItem.findMany.mockResolvedValue([
      item({ categoryId: 'c1', categoryName: 'Boissons', quantity: 1, unitPrice: 100 }),
      item({ categoryId: 'c2', categoryName: 'Plats', quantity: 1, unitPrice: 500 }),
    ]);

    const result = await service.weeklyByCategory('est-1', 'revenue', '2026-09-07', 'c1');

    expect(result.series).toHaveLength(1);
    expect(result.series[0].name).toBe('Boissons');
  });
});

describe('ChartsService.weeklyByProduct', () => {
  it('filters to a single product when productId is given', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.saleItem.findMany.mockResolvedValue([
      item({ productId: 'p1', name: 'Bière', quantity: 1, unitPrice: 1000 }),
      item({ productId: 'p2', name: 'Soda', quantity: 1, unitPrice: 500 }),
    ]);

    const result = await service.weeklyByProduct('est-1', 'revenue', '2026-09-07', 'p2');

    expect(result.series).toHaveLength(1);
    expect(result.series[0].name).toBe('Soda');
  });
});

describe('ChartsService.monthly', () => {
  it('buckets by month for the given year, ignoring other years', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.saleItem.findMany.mockResolvedValue([
      item({ createdAt: new Date('2026-01-15T10:00:00Z'), quantity: 1, unitPrice: 100 }),
      item({ createdAt: new Date('2026-03-02T10:00:00Z'), quantity: 1, unitPrice: 200 }),
    ]);

    const result = await service.monthly('est-1', 'revenue', 2026);

    expect(result.year).toBe(2026);
    expect(result.months[0]).toEqual({ month: 'Janvier', value: 100 });
    expect(result.months[1]).toEqual({ month: 'Février', value: 0 });
    expect(result.months[2]).toEqual({ month: 'Mars', value: 200 });
  });
});

describe('ChartsService.top', () => {
  it('ranks categories by revenue for the "revenue" metric', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.saleItem.findMany.mockResolvedValue([
      item({ categoryId: 'c1', categoryName: 'Boissons', quantity: 1, unitPrice: 100 }),
      item({ categoryId: 'c2', categoryName: 'Plats', quantity: 1, unitPrice: 500 }),
    ]);

    const result = await service.top('est-1', 'revenue', new Date('2026-01-01'), new Date('2026-12-31'));

    expect(result.groupBy).toBe('category');
    expect(result.items[0]).toEqual({ id: 'c2', name: 'Plats', value: 500 });
  });

  it('ranks individual products by profit for the "profit" metric, capped at 10', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.saleItem.findMany.mockResolvedValue(
      Array.from({ length: 12 }, (_, i) =>
        item({ productId: `p${i}`, name: `Produit ${i}`, quantity: 1, unitPrice: 100 + i, purchasePrice: 50 }),
      ),
    );

    const result = await service.top('est-1', 'profit', new Date('2026-01-01'), new Date('2026-12-31'));

    expect(result.groupBy).toBe('product');
    expect(result.items).toHaveLength(10);
    expect(result.items[0].name).toBe('Produit 11');
  });
});

describe('ChartsService.stockLots', () => {
  it('throws NotFoundException when the product does not belong to this establishment', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.product.findFirst.mockResolvedValue(null);

    await expect(service.stockLots('est-1', 'missing')).rejects.toThrow('Produit introuvable');
  });

  it('reconstructs FIFO lots from the movement history and separates active lots from full history', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.product.findFirst.mockResolvedValue({ id: 'p1', name: 'Bière Flag 65cl' });
    prisma.stockMovement.findMany.mockResolvedValue([
      { type: 'in', quantity: new Decimal(100), createdAt: new Date('2025-08-20T08:00:00Z') },
      { type: 'in', quantity: new Decimal(150), createdAt: new Date('2025-09-05T08:00:00Z') },
      { type: 'in', quantity: new Decimal(120), createdAt: new Date('2025-09-10T08:00:00Z') },
      { type: 'sale', quantity: new Decimal(100), createdAt: new Date('2025-09-11T09:00:00Z') },
      { type: 'sale', quantity: new Decimal(70), createdAt: new Date('2025-09-12T09:00:00Z') },
    ]);

    const result = await service.stockLots('est-1', 'p1');

    expect(result.productId).toBe('p1');
    expect(result.productName).toBe('Bière Flag 65cl');
    expect(result.historyLots).toHaveLength(3);
    expect(result.activeLots.map((l) => l.code)).toEqual(['L002', 'L003']);
    expect(result.totalActiveUnits).toBe(200);
    expect(prisma.stockMovement.findMany).toHaveBeenCalledWith({
      where: { productId: 'p1' },
      orderBy: { createdAt: 'asc' },
      select: { type: true, quantity: true, createdAt: true },
    });
  });

  it('returns empty lot lists and a zero total for a product with no stock movements yet', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.product.findFirst.mockResolvedValue({ id: 'p1', name: 'Nouveau produit' });
    prisma.stockMovement.findMany.mockResolvedValue([]);

    const result = await service.stockLots('est-1', 'p1');

    expect(result.activeLots).toEqual([]);
    expect(result.historyLots).toEqual([]);
    expect(result.totalActiveUnits).toBe(0);
  });
});

describe('ChartsService — sous-module Dépenses', () => {
  it('expensesWeeklyTotal buckets by weekday (Monday-first), same convention as weeklyTotal', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.expense.findMany.mockResolvedValue([
      expense({ createdAt: new Date('2026-09-07T10:00:00Z'), amount: 5000 }), // Lundi
      expense({ createdAt: new Date('2026-09-09T10:00:00Z'), amount: 3000 }), // Mercredi
    ]);

    const result = await service.expensesWeeklyTotal('est-1', '2026-09-07');

    expect(result.weekStart).toBe('2026-09-07');
    expect(result.series).toHaveLength(1);
    expect(result.series[0].points[0]).toEqual({ day: 'Lundi', value: 5000 });
    expect(result.series[0].points[2]).toEqual({ day: 'Mercredi', value: 3000 });
  });

  it('expensesWeeklyByCategory groups by category, "Sans catégorie" for null, sorted by total descending', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.expense.findMany.mockResolvedValue([
      expense({ category: 'Loyer', amount: 50000 }),
      expense({ category: 'Eau', amount: 5000 }),
      expense({ category: null, amount: 1000 }),
    ]);

    const result = await service.expensesWeeklyByCategory('est-1', '2026-09-07');

    expect(result.series.map((s) => s.name)).toEqual(['Loyer', 'Eau', 'Sans catégorie']);
  });

  it('expensesWeeklyByCategory filters to a single category when given', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.expense.findMany.mockResolvedValue([
      expense({ category: 'Loyer', amount: 50000 }),
      expense({ category: 'Eau', amount: 5000 }),
    ]);

    const result = await service.expensesWeeklyByCategory('est-1', '2026-09-07', 'Eau');

    expect(result.series).toHaveLength(1);
    expect(result.series[0].name).toBe('Eau');
  });

  it('expensesMonthly buckets by month for the given year', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.expense.findMany.mockResolvedValue([
      expense({ createdAt: new Date('2026-01-15T10:00:00Z'), amount: 50000 }),
      expense({ createdAt: new Date('2026-03-02T10:00:00Z'), amount: 20000 }),
    ]);

    const result = await service.expensesMonthly('est-1', 2026);

    expect(result.months[0]).toEqual({ month: 'Janvier', value: 50000 });
    expect(result.months[1]).toEqual({ month: 'Février', value: 0 });
    expect(result.months[2]).toEqual({ month: 'Mars', value: 20000 });
  });

  it('expensesTop ranks categories by total amount, capped at 10', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.expense.findMany.mockResolvedValue(
      Array.from({ length: 12 }, (_, i) => expense({ category: `Cat${i}`, amount: 100 + i })),
    );

    const result = await service.expensesTop('est-1', new Date('2026-01-01'), new Date('2026-12-31'));

    expect(result.groupBy).toBe('category');
    expect(result.items).toHaveLength(10);
    expect(result.items[0].name).toBe('Cat11');
  });
});
