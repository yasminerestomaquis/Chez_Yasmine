import { Decimal } from '@prisma/client';
import { describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import { ChartsService } from './charts.service.js';

function makePrismaMock() {
  return {
    saleItem: { findMany: vi.fn() },
    product: { findFirst: vi.fn(), findMany: vi.fn() },
    stockMovement: { findMany: vi.fn() },
    expense: { findMany: vi.fn() },
    purchase: { findMany: vi.fn() },
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
  hasVariablePricing?: boolean;
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
          : {
              name: overrides.categoryName ?? 'Boissons',
              hasCasePricing: overrides.hasCasePricing ?? false,
              hasVariablePricing: overrides.hasVariablePricing ?? false,
            },
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

  it('filters to a single category when categoryIds is given', async () => {
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

  it('aggregates several selected categories into a single summed series', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.saleItem.findMany.mockResolvedValue([
      item({ categoryId: 'c1', categoryName: 'Boissons', quantity: 1, unitPrice: 100 }),
      item({ categoryId: 'c2', categoryName: 'Plats', quantity: 1, unitPrice: 500 }),
      item({ categoryId: 'c3', categoryName: 'Desserts', quantity: 1, unitPrice: 50 }),
    ]);

    const result = await service.weeklyByCategory('est-1', 'revenue', '2026-09-07', 'c1,c2');

    expect(result.series).toHaveLength(1);
    expect(result.series[0].name).toBe('2 catégories sélectionnées');
    expect(result.series[0].points.reduce((sum, p) => sum + p.value, 0)).toBe(600);
  });
});

describe('ChartsService — répartition du coût "Marché" (Poulets/Poissons/Plats africains)', () => {
  it('allocates a day\'s Marché expense across variable-pricing sales, pro-rata to that day\'s revenue', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    // Lundi 07/09 : Poulet (CA 700) et Poisson (CA 300) — même jour, même catégorie tag.
    prisma.saleItem.findMany.mockResolvedValue([
      item({
        productId: 'p-poulet',
        name: 'Poulet',
        categoryId: 'c-poulet',
        categoryName: 'Poulets',
        hasVariablePricing: true,
        quantity: 1,
        unitPrice: 700,
        createdAt: new Date('2026-09-07T12:00:00Z'),
      }),
      item({
        productId: 'p-poisson',
        name: 'Poisson',
        categoryId: 'c-poisson',
        categoryName: 'Poissons',
        hasVariablePricing: true,
        quantity: 1,
        unitPrice: 300,
        createdAt: new Date('2026-09-07T12:00:00Z'),
      }),
    ]);
    prisma.expense.findMany.mockResolvedValue([expense({ amount: 1000, category: 'Marché', createdAt: new Date('2026-09-07T09:00:00Z') })]);

    const result = await service.weeklyByCategory('est-1', 'profit', '2026-09-07');

    const poulet = result.series.find((s) => s.name === 'Poulets')!;
    const poisson = result.series.find((s) => s.name === 'Poissons')!;
    // Poulet : 70% du CA du jour → 700 de coût alloué → bénéfice 0. Poisson : 30% → 300 → bénéfice 0.
    expect(poulet.points.reduce((sum, p) => sum + p.value, 0)).toBeCloseTo(0);
    expect(poisson.points.reduce((sum, p) => sum + p.value, 0)).toBeCloseTo(0);
    expect(prisma.expense.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: expect.objectContaining({ establishmentId: 'est-1', category: 'Marché' }) }),
    );
  });

  it('does not allocate any cost on a day with no Marché expense, even with variable-pricing sales', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.saleItem.findMany.mockResolvedValue([
      // purchasePrice: 0, comme en production — ProductsService force toujours
      // Product.purchasePrice à null pour une catégorie hasVariablePricing.
      item({ categoryId: 'c-poulet', categoryName: 'Poulets', hasVariablePricing: true, quantity: 1, unitPrice: 700, purchasePrice: 0 }),
    ]);
    prisma.expense.findMany.mockResolvedValue([]);

    const result = await service.weeklyByCategory('est-1', 'profit', '2026-09-07');

    expect(result.series[0].points.reduce((sum, p) => sum + p.value, 0)).toBe(700);
  });

  it('never queries expenses when no line belongs to a variable-pricing category', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.saleItem.findMany.mockResolvedValue([item({ hasCasePricing: true, purchasePrice: 60, quantity: 1, unitPrice: 100 })]);

    await service.weeklyTotal('est-1', 'profit', '2026-09-07');

    expect(prisma.expense.findMany).not.toHaveBeenCalled();
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
  it('throws NotFoundException when a requested product does not belong to this establishment', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.product.findMany.mockResolvedValue([]);

    await expect(service.stockLots('est-1', ['missing'])).rejects.toThrow('introuvable');
  });

  it('throws BadRequestException when the selected products span more than one category', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.product.findMany.mockResolvedValue([
      { id: 'p1', name: 'Bière', categoryId: 'c1', category: { name: 'Bières', hasCasePricing: true, hasVariablePricing: false } },
      { id: 'p2', name: 'Poulet', categoryId: 'c2', category: { name: 'Poulets', hasCasePricing: false, hasVariablePricing: true } },
    ]);

    await expect(service.stockLots('est-1', ['p1', 'p2'])).rejects.toThrow('même catégorie');
  });

  it('renumbers a lot with the order number parsed from its reason, and hides it when no matching purchase exists', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.product.findMany.mockResolvedValue([
      { id: 'p1', name: 'Bière Flag 65cl', categoryId: 'c1', category: { name: 'Bières', hasCasePricing: true, hasVariablePricing: false } },
    ]);
    prisma.stockMovement.findMany.mockResolvedValue([
      { productId: 'p1', type: 'in', quantity: new Decimal(100), createdAt: new Date('2025-08-20T08:00:00Z'), reason: 'Commande n°1' },
      { productId: 'p1', type: 'in', quantity: new Decimal(120), createdAt: new Date('2025-09-10T08:00:00Z'), reason: 'Commande n°3' },
      { productId: 'p1', type: 'sale', quantity: new Decimal(30), createdAt: new Date('2025-09-11T09:00:00Z'), reason: null },
    ]);
    // Seule la commande n°1 existe réellement pour cet établissement : le lot
    // "n°3" (référence parsée mais sans commande correspondante) doit être masqué.
    prisma.purchase.findMany.mockResolvedValue([{ orderNumber: 1 }]);

    const result = await service.stockLots('est-1', ['p1']);

    expect(result.historyLots).toHaveLength(1);
    expect(result.historyLots[0]).toMatchObject({ code: 'L001', referenceNumber: 1, remainingQuantity: 70 });
    expect(result.totalActiveUnits).toBe(70);
    expect(prisma.purchase.findMany).toHaveBeenCalledWith({
      where: { establishmentId: 'est-1', orderNumber: { in: expect.arrayContaining([1, 3]) } },
      select: { orderNumber: true },
    });
  });

  it('combines lots from several products of the same category, tagging each with its own product name', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.product.findMany.mockResolvedValue([
      { id: 'p1', name: 'Bière Flag 65cl', categoryId: 'c1', category: { name: 'Bières', hasCasePricing: true, hasVariablePricing: false } },
      { id: 'p2', name: 'Bière Beaufort', categoryId: 'c1', category: { name: 'Bières', hasCasePricing: true, hasVariablePricing: false } },
    ]);
    prisma.stockMovement.findMany.mockResolvedValue([
      { productId: 'p1', type: 'in', quantity: new Decimal(50), createdAt: new Date('2025-08-20T08:00:00Z'), reason: 'Commande n°1' },
      { productId: 'p2', type: 'in', quantity: new Decimal(60), createdAt: new Date('2025-08-20T08:00:00Z'), reason: 'Commande n°1' },
    ]);
    prisma.purchase.findMany.mockResolvedValue([{ orderNumber: 1 }]);

    const result = await service.stockLots('est-1', ['p1', 'p2']);

    expect(result.productIds).toEqual(['p1', 'p2']);
    expect(result.historyLots.map((l) => l.productName)).toEqual(['Bière Flag 65cl', 'Bière Beaufort']);
    expect(result.totalActiveUnits).toBe(110);
  });

  it('reports lossQuantity separately from other consumption on a lot', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.product.findMany.mockResolvedValue([
      { id: 'p1', name: 'Poulet braisé', categoryId: 'c3', category: { name: 'Poulets', hasCasePricing: false, hasVariablePricing: true } },
    ]);
    prisma.stockMovement.findMany.mockResolvedValue([
      { productId: 'p1', type: 'in', quantity: new Decimal(20), createdAt: new Date('2026-01-01T00:00:00Z'), reason: 'Marché n°2' },
      { productId: 'p1', type: 'loss', quantity: new Decimal(5), createdAt: new Date('2026-01-02T00:00:00Z'), reason: null },
    ]);
    prisma.expense.findMany.mockResolvedValue([{ marketNumber: 2 }]);

    const result = await service.stockLots('est-1', ['p1']);

    expect(result.historyLots[0]).toMatchObject({ code: 'L002', consumedQuantity: 5, lossQuantity: 5, remainingQuantity: 15 });
    expect(prisma.expense.findMany).toHaveBeenCalledWith({
      where: { establishmentId: 'est-1', category: 'Marché', marketNumber: { in: [2] } },
      select: { marketNumber: true },
    });
  });

  it('returns empty lot lists and a zero total for a product with no stock movements yet', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.product.findMany.mockResolvedValue([
      { id: 'p1', name: 'Nouveau produit', categoryId: 'c1', category: { name: 'Bières', hasCasePricing: true, hasVariablePricing: false } },
    ]);
    prisma.stockMovement.findMany.mockResolvedValue([]);

    const result = await service.stockLots('est-1', ['p1']);

    expect(result.activeLots).toEqual([]);
    expect(result.historyLots).toEqual([]);
    expect(result.totalActiveUnits).toBe(0);
    expect(prisma.purchase.findMany).not.toHaveBeenCalled();
  });
});

describe('ChartsService.outOfStockProducts', () => {
  it('lists active products at or below zero stock, sorted alphabetically', async () => {
    const prisma = makePrismaMock();
    const service = new ChartsService(prisma as unknown as PrismaService);
    prisma.product.findMany.mockResolvedValue([
      { id: 'p1', name: 'Bière Beaufort', stockQuantity: new Decimal(0), category: { name: 'Bières' } },
      { id: 'p2', name: 'Poisson braisé', stockQuantity: new Decimal(0), category: null },
    ]);

    const result = await service.outOfStockProducts('est-1');

    expect(result).toEqual([
      { id: 'p1', name: 'Bière Beaufort', categoryName: 'Bières', stockQuantity: 0 },
      { id: 'p2', name: 'Poisson braisé', categoryName: 'Sans catégorie', stockQuantity: 0 },
    ]);
    expect(prisma.product.findMany).toHaveBeenCalledWith({
      where: { establishmentId: 'est-1', status: 'active', stockQuantity: { lte: 0 } },
      select: { id: true, name: true, stockQuantity: true, category: { select: { name: true } } },
      orderBy: { name: 'asc' },
    });
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
