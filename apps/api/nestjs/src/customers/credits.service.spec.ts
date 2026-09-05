import { BadRequestException, NotFoundException } from '@nestjs/common';
import { Decimal } from '@prisma/client';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import { CreditsService } from './credits.service.js';

function makePrismaMock() {
  const prisma: Record<string, unknown> = {
    customer: { findFirst: vi.fn(), update: vi.fn() },
    credit: { findMany: vi.fn() },
    creditPayment: { findMany: vi.fn(), create: vi.fn() },
    $transaction: vi.fn(async (ops: unknown[]) => ops),
  };
  return prisma;
}

describe('CreditsService.history', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: CreditsService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new CreditsService(prisma as unknown as PrismaService);
  });

  it('throws NotFoundException for a customer outside the establishment', async () => {
    (prisma.customer as any).findFirst.mockResolvedValue(null);
    await expect(service.history('est-1', 'cust-x')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('merges credits and repayments into one list, most recent first', async () => {
    (prisma.customer as any).findFirst.mockResolvedValue({ id: 'cust-1' });
    (prisma.credit as any).findMany.mockResolvedValue([
      { amount: new Decimal(2000), saleId: 'sale-1', createdAt: new Date('2026-01-01') },
    ]);
    (prisma.creditPayment as any).findMany.mockResolvedValue([{ amount: new Decimal(500), createdAt: new Date('2026-01-02') }]);

    const history = await service.history('est-1', 'cust-1');

    expect(history).toEqual([
      { type: 'repayment', amount: 500, createdAt: new Date('2026-01-02') },
      { type: 'credit', amount: 2000, saleId: 'sale-1', createdAt: new Date('2026-01-01') },
    ]);
  });
});

describe('CreditsService.recordRepayment', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: CreditsService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new CreditsService(prisma as unknown as PrismaService);
  });

  it('rejects a repayment larger than the current balance, before any write', async () => {
    (prisma.customer as any).findFirst.mockResolvedValue({ id: 'cust-1', creditBalance: new Decimal(500) });
    await expect(service.recordRepayment('est-1', 'cust-1', { amount: 1000 })).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('decreases the balance and records the payment in one transaction', async () => {
    (prisma.customer as any).findFirst.mockResolvedValue({ id: 'cust-1', creditBalance: new Decimal(3000) });

    await service.recordRepayment('est-1', 'cust-1', { amount: 1000 });

    expect(prisma.customer.update).toHaveBeenCalledWith({ where: { id: 'cust-1' }, data: { creditBalance: 2000 } });
    expect(prisma.creditPayment.create).toHaveBeenCalledWith({ data: { customerId: 'cust-1', amount: 1000 } });
  });
});
