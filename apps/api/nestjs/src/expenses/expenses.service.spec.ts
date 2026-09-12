import { NotFoundException } from '@nestjs/common';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import type { ActivityNotifierService } from '../notifications/activity-notifier.service.js';
import { ExpensesService } from './expenses.service.js';

const activityNotifierMock = { notify: vi.fn() } as unknown as ActivityNotifierService;

function makePrismaMock() {
  const prisma: Record<string, unknown> = {
    expense: {
      findMany: vi.fn(),
      findFirst: vi.fn(),
      create: vi.fn(),
      updateMany: vi.fn(),
      findUniqueOrThrow: vi.fn(),
      deleteMany: vi.fn(),
    },
  };
  return prisma;
}

describe('ExpensesService.list', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: ExpensesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new ExpensesService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('scopes by establishment and orders by expenseDate descending, with no date filter by default', async () => {
    (prisma.expense as any).findMany.mockResolvedValue([]);
    await service.list('est-1');
    expect(prisma.expense.findMany).toHaveBeenCalledWith({
      where: { establishmentId: 'est-1' },
      orderBy: { expenseDate: 'desc' },
    });
  });

  it('adds an expenseDate range filter when from/to are given', async () => {
    (prisma.expense as any).findMany.mockResolvedValue([]);
    await service.list('est-1', { from: '2026-09-01', to: '2026-09-30' });
    expect(prisma.expense.findMany).toHaveBeenCalledWith({
      where: {
        establishmentId: 'est-1',
        expenseDate: { gte: new Date('2026-09-01'), lte: new Date('2026-09-30') },
      },
      orderBy: { expenseDate: 'desc' },
    });
  });
});

describe('ExpensesService.update / remove', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: ExpensesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new ExpensesService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('throws NotFoundException updating an expense outside the establishment', async () => {
    (prisma.expense as any).updateMany.mockResolvedValue({ count: 0 });
    await expect(service.update('est-1', 'exp-x', { amount: 100 })).rejects.toBeInstanceOf(NotFoundException);
  });

  it('throws NotFoundException removing an expense outside the establishment', async () => {
    (prisma.expense as any).deleteMany.mockResolvedValue({ count: 0 });
    await expect(service.remove('est-1', 'exp-x')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('removes an expense that belongs to the establishment', async () => {
    (prisma.expense as any).deleteMany.mockResolvedValue({ count: 1 });
    await expect(service.remove('est-1', 'exp-1')).resolves.toBeUndefined();
  });
});

describe('ExpensesService.create', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: ExpensesService;

  beforeEach(() => {
    vi.mocked(activityNotifierMock.notify).mockClear();
    prisma = makePrismaMock();
    service = new ExpensesService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('defaults periodicity to one_off when not given', async () => {
    (prisma.expense as any).create.mockResolvedValue({ id: 'exp-1' });
    await service.create('est-1', { label: 'Loyer', amount: 50000 });
    expect(prisma.expense.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ periodicity: 'one_off' }),
    });
  });

  it('notifies the organization of the new expense (visible in Notifications)', async () => {
    (prisma.expense as any).create.mockResolvedValue({ id: 'exp-1' });
    await service.create('est-1', { label: 'Loyer', amount: 50000, category: 'Loyer' });
    expect(activityNotifierMock.notify).toHaveBeenCalledWith(
      'est-1',
      'Nouvelle dépense',
      expect.stringContaining('Loyer'),
    );
  });

  it('does not notify again when replaying an already-recorded expense (idempotent sync retry)', async () => {
    (prisma.expense as any).findFirst.mockResolvedValue({ id: 'exp-1' });
    await service.create('est-1', { id: 'exp-1', label: 'Loyer', amount: 50000 });
    expect(activityNotifierMock.notify).not.toHaveBeenCalled();
  });

  it('passes through an explicit periodicity', async () => {
    (prisma.expense as any).create.mockResolvedValue({ id: 'exp-1' });
    await service.create('est-1', { label: 'Loyer', amount: 50000, periodicity: 'recurring' });
    expect(prisma.expense.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ periodicity: 'recurring' }),
    });
  });

  it('replays an idempotent create instead of inserting a duplicate (offline sync retry)', async () => {
    (prisma.expense as any).findFirst.mockResolvedValue({ id: 'exp-1', label: 'Loyer' });
    const result = await service.create('est-1', { id: 'exp-1', label: 'Loyer', amount: 50000 });
    expect(result).toEqual({ id: 'exp-1', label: 'Loyer' });
    expect(prisma.expense.create).not.toHaveBeenCalled();
  });

  it('passes through an explicit marketNumber', async () => {
    (prisma.expense as any).create.mockResolvedValue({ id: 'exp-1' });
    await service.create('est-1', { label: 'Achat du jour', amount: 15000, category: 'Marché', marketNumber: 3 });
    expect(prisma.expense.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ marketNumber: 3 }),
    });
  });
});

describe('ExpensesService.nextMarketNumber', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: ExpensesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new ExpensesService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('returns 1 when no "Marché" expense exists yet', async () => {
    (prisma.expense as any).findFirst.mockResolvedValue(null);
    await expect(service.nextMarketNumber('est-1')).resolves.toBe(1);
    expect(prisma.expense.findFirst).toHaveBeenCalledWith({
      where: { establishmentId: 'est-1', category: 'Marché' },
      orderBy: { marketNumber: 'desc' },
      select: { marketNumber: true },
    });
  });

  it('returns last + 1, scoped to category "Marché"', async () => {
    (prisma.expense as any).findFirst.mockResolvedValue({ marketNumber: 4 });
    await expect(service.nextMarketNumber('est-1')).resolves.toBe(5);
  });
});

describe('ExpensesService.summary', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: ExpensesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new ExpensesService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('resolves a "month" period to that calendar month\'s bounds', async () => {
    (prisma.expense as any).findMany.mockResolvedValue([]);
    const result = await service.summary('est-1', { period: 'month', year: 2026, month: 9 });
    expect(result.from.toISOString().slice(0, 10)).toBe('2026-09-01');
    expect(result.to.toISOString().slice(0, 10)).toBe('2026-09-30');
  });

  it('splits totals: total, Salaires, Marché, and "charges fixes" (everything else)', async () => {
    (prisma.expense as any).findMany.mockResolvedValue([
      { category: 'Salaires', amount: { toNumber: () => 620000 }, expenseDate: new Date('2026-09-08') },
      { category: 'Marché', amount: { toNumber: () => 280000 }, expenseDate: new Date('2026-09-12') },
      { category: 'Loyer', amount: { toNumber: () => 150000 }, expenseDate: new Date('2026-09-01') },
      { category: 'Eau', amount: { toNumber: () => 18500 }, expenseDate: new Date('2026-09-10') },
    ]);
    const result = await service.summary('est-1', { period: 'month', year: 2026, month: 9 });
    expect(result.totalAmount).toBe(1068500);
    expect(result.totalSalaries).toBe(620000);
    expect(result.totalMarket).toBe(280000);
    expect(result.totalFixedCharges).toBe(168500);
  });

  it('computes a percentage-change comparison against the equivalent previous period', async () => {
    (prisma.expense as any).findMany
      .mockResolvedValueOnce([{ category: 'Loyer', amount: { toNumber: () => 200000 }, expenseDate: new Date('2026-09-01') }])
      .mockResolvedValueOnce([{ category: 'Loyer', amount: { toNumber: () => 100000 }, expenseDate: new Date('2026-08-01') }]);
    const result = await service.summary('est-1', { period: 'month', year: 2026, month: 9 });
    expect(result.totalAmount).toBe(200000);
    expect(result.previousTotalAmount).toBe(100000);
    expect(result.changePercent).toBe(100);
  });

  it('groups a category breakdown for the donut chart', async () => {
    (prisma.expense as any).findMany.mockResolvedValue([
      { category: 'Loyer', amount: { toNumber: () => 150000 }, expenseDate: new Date('2026-09-01') },
      { category: 'Loyer', amount: { toNumber: () => 50000 }, expenseDate: new Date('2026-09-05') },
      { category: null, amount: { toNumber: () => 10000 }, expenseDate: new Date('2026-09-06') },
    ]);
    const result = await service.summary('est-1', { period: 'month', year: 2026, month: 9 });
    expect(result.byCategory).toEqual(
      expect.arrayContaining([
        { category: 'Loyer', amount: 200000 },
        { category: 'Autre', amount: 10000 },
      ]),
    );
  });
});
