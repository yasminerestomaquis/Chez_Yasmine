import { Decimal } from '@prisma/client';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import type { StockMovementsService } from '../stock/stock-movements.service.js';
import { ReportsService } from './reports.service.js';

function makePrismaMock() {
  const prisma: Record<string, unknown> = {
    sale: { findMany: vi.fn() },
    expense: { aggregate: vi.fn() },
    loss: { findMany: vi.fn() },
    customer: { aggregate: vi.fn() },
    product: { findMany: vi.fn() },
    userProfile: { findMany: vi.fn() },
  };
  return prisma;
}

function makeStockMovementsMock() {
  return { listLowStockAlerts: vi.fn().mockResolvedValue([]) };
}

describe('ReportsService.resolveRange', () => {
  const service = new ReportsService(
    makePrismaMock() as unknown as PrismaService,
    makeStockMovementsMock() as unknown as StockMovementsService,
  );

  it('uses an explicit from/to over any period', () => {
    const range = service.resolveRange({ from: '2026-01-01', to: '2026-01-31', period: 'year' });
    expect(range.from).toEqual(new Date('2026-01-01'));
    expect(range.to).toEqual(new Date('2026-01-31'));
  });

  it('defaults to the start of today when nothing is given', () => {
    const range = service.resolveRange({});
    expect(range.from.getHours()).toBe(0);
    expect(range.from.getMinutes()).toBe(0);
    expect(range.to.getTime()).toBeGreaterThanOrEqual(range.from.getTime());
  });

  it('resolves "month" to roughly 30 days before now', () => {
    const range = service.resolveRange({ period: 'month' });
    const diffDays = (range.to.getTime() - range.from.getTime()) / (1000 * 60 * 60 * 24);
    expect(diffDays).toBeGreaterThan(27);
    expect(diffDays).toBeLessThan(32);
  });
});

describe('ReportsService.summary', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let stockMovements: ReturnType<typeof makeStockMovementsMock>;
  let service: ReportsService;

  beforeEach(() => {
    prisma = makePrismaMock();
    stockMovements = makeStockMovementsMock();
    service = new ReportsService(prisma as unknown as PrismaService, stockMovements as unknown as StockMovementsService);

    (prisma.expense as any).aggregate.mockResolvedValue({ _sum: { amount: new Decimal(5000) } });
    (prisma.loss as any).findMany.mockResolvedValue([]);
    (prisma.customer as any).aggregate.mockResolvedValue({ _sum: { creditBalance: new Decimal(12000) } });
    (prisma.product as any).findMany.mockResolvedValue([{ id: 'p1', purchasePrice: new Decimal(300) }]);
    (prisma.userProfile as any).findMany.mockResolvedValue([{ id: 'user-1', fullName: 'Awa' }]);
  });

  it('excludes voided sales and scopes by establishment and date range', async () => {
    (prisma.sale as any).findMany.mockResolvedValue([]);
    await service.summary('est-1', { from: '2026-09-01', to: '2026-09-05' });

    expect(prisma.sale.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ establishmentId: 'est-1', voidedAt: null }),
      }),
    );
  });

  it('computes revenue, discounts, margin, and net profit from sales/expenses/losses', async () => {
    (prisma.sale as any).findMany.mockResolvedValue([
      {
        id: 'sale-1',
        total: new Decimal(2000),
        discount: new Decimal(100),
        createdBy: 'user-1',
        items: [{ productId: 'p1', name: 'Bière', quantity: new Decimal(2), unitPrice: new Decimal(1000) }],
      },
    ]);

    const result = await service.summary('est-1', {});

    expect(result.revenue).toBe(2000);
    expect(result.discountTotal).toBe(100);
    expect(result.salesCount).toBe(1);
    expect(result.cogs).toBe(600); // 2 * 300
    expect(result.grossMargin).toBe(1400); // 2000 - 600
    expect(result.expenses).toBe(5000);
    expect(result.losses).toBe(0);
    expect(result.netProfit).toBe(1400 - 5000); // grossMargin - expenses - losses
    expect(result.receivables).toBe(12000);
  });

  it('uses purchasePricePerCase/bottlesPerCase as the cost for a case-pricing category, not purchasePrice', async () => {
    (prisma.product as any).findMany.mockResolvedValue([
      {
        id: 'p1',
        purchasePrice: new Decimal(2500), // prix "par bouteille" — ne doit PAS être utilisé ici
        bottlesPerCase: 12,
        purchasePricePerCase: new Decimal(19500),
        category: { hasCasePricing: true },
      },
    ]);
    (prisma.sale as any).findMany.mockResolvedValue([
      {
        id: 'sale-1',
        total: new Decimal(6000),
        discount: new Decimal(0),
        createdBy: null,
        items: [{ productId: 'p1', name: 'Bière 65cl', quantity: new Decimal(2), unitPrice: new Decimal(3000) }],
      },
    ]);

    const result = await service.summary('est-1', {});

    expect(result.cogs).toBe(2 * (19500 / 12)); // 3250, pas 2 × 2500 = 5000
  });

  it('falls back to purchasePrice when a case-pricing product has no bottlesPerCase/purchasePricePerCase yet', async () => {
    (prisma.product as any).findMany.mockResolvedValue([
      { id: 'p1', purchasePrice: new Decimal(2500), bottlesPerCase: null, purchasePricePerCase: null, category: { hasCasePricing: true } },
    ]);
    (prisma.sale as any).findMany.mockResolvedValue([
      {
        id: 'sale-1',
        total: new Decimal(6000),
        discount: new Decimal(0),
        createdBy: null,
        items: [{ productId: 'p1', name: 'Bière 65cl', quantity: new Decimal(2), unitPrice: new Decimal(3000) }],
      },
    ]);

    const result = await service.summary('est-1', {});

    expect(result.cogs).toBe(5000); // 2 × 2500
  });

  it('ranks topProducts by quantity sold, capped at 5', async () => {
    (prisma.sale as any).findMany.mockResolvedValue([
      {
        id: 'sale-1',
        total: new Decimal(0),
        discount: new Decimal(0),
        createdBy: null,
        items: [
          { productId: 'p1', name: 'Bière', quantity: new Decimal(10), unitPrice: new Decimal(500) },
          { productId: 'p2', name: 'Soda', quantity: new Decimal(3), unitPrice: new Decimal(500) },
        ],
      },
    ]);
    (prisma.product as any).findMany.mockResolvedValue([
      { id: 'p1', purchasePrice: new Decimal(300) },
      { id: 'p2', purchasePrice: new Decimal(200) },
    ]);

    const result = await service.summary('est-1', {});

    expect(result.topProducts[0]).toEqual({ productId: 'p1', name: 'Bière', quantity: 10, revenue: 5000, cost: 3000, profit: 2000 });
    expect(result.topProducts[1].productId).toBe('p2');
  });

  it('computes per-product profit and ranks productProfitability by profit, uncapped', async () => {
    (prisma.sale as any).findMany.mockResolvedValue([
      {
        id: 'sale-1',
        total: new Decimal(0),
        discount: new Decimal(0),
        createdBy: null,
        items: [
          { productId: 'p1', name: 'Bière', quantity: new Decimal(2), unitPrice: new Decimal(1000) },
          { productId: 'p2', name: 'Soda', quantity: new Decimal(10), unitPrice: new Decimal(500) },
        ],
      },
    ]);
    (prisma.product as any).findMany.mockResolvedValue([
      { id: 'p1', purchasePrice: new Decimal(300) },
      { id: 'p2', purchasePrice: new Decimal(450) },
    ]);

    const result = await service.summary('est-1', {});

    // p1: revenue 2000, cost 600, profit 1400. p2: revenue 5000, cost 4500, profit 500.
    expect(result.productProfitability).toEqual([
      { productId: 'p1', name: 'Bière', quantity: 2, revenue: 2000, cost: 600, profit: 1400 },
      { productId: 'p2', name: 'Soda', quantity: 10, revenue: 5000, cost: 4500, profit: 500 },
    ]);
  });

  it('aggregates serverPerformance by createdBy, ignoring sales with no server', async () => {
    (prisma.sale as any).findMany.mockResolvedValue([
      { id: 's1', total: new Decimal(1000), discount: new Decimal(0), createdBy: 'user-1', items: [] },
      { id: 's2', total: new Decimal(500), discount: new Decimal(0), createdBy: 'user-1', items: [] },
      { id: 's3', total: new Decimal(700), discount: new Decimal(0), createdBy: null, items: [] },
    ]);

    const result = await service.summary('est-1', {});

    expect(result.serverPerformance).toEqual([{ userId: 'user-1', name: 'Awa', total: 1500, salesCount: 2 }]);
  });
});

describe('ReportsService.summaryCsv', () => {
  it('renders the summary as a header row plus one row per indicator', async () => {
    const prisma = makePrismaMock();
    const stockMovements = makeStockMovementsMock();
    (prisma.sale as any).findMany.mockResolvedValue([]);
    (prisma.expense as any).aggregate.mockResolvedValue({ _sum: { amount: null } });
    (prisma.loss as any).findMany.mockResolvedValue([]);
    (prisma.customer as any).aggregate.mockResolvedValue({ _sum: { creditBalance: null } });
    const service = new ReportsService(prisma as unknown as PrismaService, stockMovements as unknown as StockMovementsService);

    const csv = await service.summaryCsv('est-1', {});

    expect(csv.split('\n')[0]).toBe('"Indicateur","Valeur"');
    expect(csv).toContain('"Chiffre d\'affaires",0');
  });
});
