import { Decimal } from '@prisma/client';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import type { ActivityNotifierService } from '../notifications/activity-notifier.service.js';
import { CashService } from './cash.service.js';

const activityNotifierMock = { notify: vi.fn() } as unknown as ActivityNotifierService;

function makePrismaMock() {
  const prisma: Record<string, unknown> = {
    pointOfSale: { findFirst: vi.fn(), create: vi.fn() },
    cashRegister: { create: vi.fn() },
    payment: { aggregate: vi.fn() },
    expense: { aggregate: vi.fn() },
    cashClosing: { create: vi.fn(), findMany: vi.fn(), findFirst: vi.fn() },
  };
  return prisma;
}

describe('CashService.close', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: CashService;

  beforeEach(() => {
    vi.mocked(activityNotifierMock.notify).mockClear();
    prisma = makePrismaMock();
    service = new CashService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('notifies the organization of the closing, with the counted amount and the difference', async () => {
    (prisma.pointOfSale as any).findFirst.mockResolvedValue({ id: 'pos-1', cashRegisters: [{ id: 'reg-1' }] });
    (prisma.payment as any).aggregate.mockResolvedValue({ _sum: { amount: new Decimal(20000) } });
    (prisma.expense as any).aggregate.mockResolvedValue({ _sum: { amount: new Decimal(0) } });
    (prisma.cashClosing as any).create.mockResolvedValue({ id: 'closing-1', expectedAmount: new Decimal(20000), countedAmount: new Decimal(19000) });

    await service.close('est-1', 'user-1', { openedAt: '2026-09-05T06:00:00.000Z', countedAmount: 19000 });

    expect(activityNotifierMock.notify).toHaveBeenCalledWith(
      'est-1',
      'Clôture de caisse',
      expect.stringContaining('19'),
    );
  });

  it('replays an already-created closing (same client id) without recreating it', async () => {
    const existing = { id: 'closing-1', expectedAmount: new Decimal(20000), countedAmount: new Decimal(19000) };
    (prisma.cashClosing as any).findFirst.mockResolvedValue(existing);

    const result = await service.close('est-1', 'user-1', {
      id: 'closing-1',
      openedAt: '2026-09-05T06:00:00.000Z',
      countedAmount: 19000,
    });

    expect(result).toEqual({ ...existing, difference: -1000 });
    expect(prisma.cashClosing.create).not.toHaveBeenCalled();
    expect(prisma.pointOfSale.findFirst).not.toHaveBeenCalled();
  });

  it('creates a default point of sale and register on first use', async () => {
    (prisma.pointOfSale as any).findFirst.mockResolvedValue(null);
    (prisma.pointOfSale as any).create.mockResolvedValue({ id: 'pos-1' });
    (prisma.cashRegister as any).create.mockResolvedValue({ id: 'reg-1' });
    (prisma.payment as any).aggregate.mockResolvedValue({ _sum: { amount: new Decimal(0) } });
    (prisma.expense as any).aggregate.mockResolvedValue({ _sum: { amount: null } });
    (prisma.cashClosing as any).create.mockResolvedValue({ id: 'closing-1', expectedAmount: new Decimal(0), countedAmount: new Decimal(0) });

    await service.close('est-1', 'user-1', { openedAt: '2026-09-05T06:00:00.000Z', countedAmount: 0 });

    expect(prisma.pointOfSale.create).toHaveBeenCalledWith({ data: { establishmentId: 'est-1', name: 'Caisse principale' } });
    expect(prisma.cashRegister.create).toHaveBeenCalledWith({ data: { pointOfSaleId: 'pos-1', name: 'Caisse' } });
  });

  it('reuses an existing register instead of creating a new one', async () => {
    (prisma.pointOfSale as any).findFirst.mockResolvedValue({ id: 'pos-1', cashRegisters: [{ id: 'reg-1' }] });
    (prisma.payment as any).aggregate.mockResolvedValue({ _sum: { amount: new Decimal(50000) } });
    (prisma.expense as any).aggregate.mockResolvedValue({ _sum: { amount: new Decimal(5000) } });
    (prisma.cashClosing as any).create.mockResolvedValue({
      id: 'closing-1',
      cashRegisterId: 'reg-1',
      expectedAmount: new Decimal(45000),
      countedAmount: new Decimal(44000),
    });

    const result = await service.close('est-1', 'user-1', { openedAt: '2026-09-05T06:00:00.000Z', countedAmount: 44000 });

    expect(prisma.pointOfSale.create).not.toHaveBeenCalled();
    expect(prisma.cashRegister.create).not.toHaveBeenCalled();
    expect(prisma.cashClosing.create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ cashRegisterId: 'reg-1', expectedAmount: 45000, countedAmount: 44000 }) }),
    );
    expect(result.difference).toBe(-1000);
  });

  it('computes expected cash as cash sale payments minus cash expenses over the period', async () => {
    (prisma.pointOfSale as any).findFirst.mockResolvedValue({ id: 'pos-1', cashRegisters: [{ id: 'reg-1' }] });
    (prisma.payment as any).aggregate.mockResolvedValue({ _sum: { amount: new Decimal(20000) } });
    (prisma.expense as any).aggregate.mockResolvedValue({ _sum: { amount: new Decimal(3000) } });
    (prisma.cashClosing as any).create.mockResolvedValue({ id: 'closing-1', expectedAmount: new Decimal(17000), countedAmount: new Decimal(17000) });

    await service.close('est-1', 'user-1', { openedAt: '2026-09-05T06:00:00.000Z', countedAmount: 17000 });

    expect(prisma.payment.aggregate).toHaveBeenCalledWith(
      expect.objectContaining({ where: expect.objectContaining({ method: 'cash' }) }),
    );
    expect(prisma.cashClosing.create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ expectedAmount: 17000 }) }),
    );
  });
});

describe('CashService.list', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: CashService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new CashService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('adds a computed difference field to each closing', async () => {
    (prisma.cashClosing as any).findMany.mockResolvedValue([
      { id: 'c1', expectedAmount: new Decimal(1000), countedAmount: new Decimal(950) },
    ]);
    const result = await service.list('est-1');
    expect(result[0].difference).toBe(-50);
  });
});
