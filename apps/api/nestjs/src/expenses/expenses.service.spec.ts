import { NotFoundException } from '@nestjs/common';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import { ExpensesService } from './expenses.service.js';

function makePrismaMock() {
  const prisma: Record<string, unknown> = {
    expense: { findMany: vi.fn(), create: vi.fn(), updateMany: vi.fn(), findUniqueOrThrow: vi.fn(), deleteMany: vi.fn() },
  };
  return prisma;
}

describe('ExpensesService.list', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: ExpensesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new ExpensesService(prisma as unknown as PrismaService);
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
    service = new ExpensesService(prisma as unknown as PrismaService);
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
