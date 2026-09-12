import { BadRequestException } from '@nestjs/common';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import type { ActivityNotifierService } from '../notifications/activity-notifier.service.js';
import { PayrollService } from './payroll.service.js';

const activityNotifierMock = { notify: vi.fn() } as unknown as ActivityNotifierService;

function makePrismaMock() {
  return {
    employee: { findMany: vi.fn() },
    payrollRun: { create: vi.fn(), findFirst: vi.fn(), findMany: vi.fn(), update: vi.fn() },
    payrollLine: { update: vi.fn(), findFirst: vi.fn() },
    expense: { create: vi.fn(), findFirst: vi.fn() },
    $transaction: vi.fn((fn: any) => (typeof fn === 'function' ? fn(makePrismaMock()) : Promise.all(fn))),
  };
}

describe('PayrollService.prepare', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: PayrollService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new PayrollService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('creates one PayrollLine per active employee, snapshotting weeklySalary as baseSalary', async () => {
    (prisma.employee as any).findMany.mockResolvedValue([
      { id: 'emp-1', weeklySalary: { toNumber: () => 30000 } },
      { id: 'emp-2', weeklySalary: { toNumber: () => 25000 } },
    ]);
    (prisma.payrollRun as any).create.mockImplementation(({ data }: any) => Promise.resolve({ id: 'run-1', ...data }));

    await service.prepare('est-1', 'user-1', { periodStart: '2026-09-07', periodEnd: '2026-09-13' });

    expect(prisma.employee.findMany).toHaveBeenCalledWith({
      where: { establishmentId: 'est-1', status: 'active' },
      select: { id: true, weeklySalary: true },
    });
    const createCall = (prisma.payrollRun as any).create.mock.calls[0][0];
    expect(createCall.data.status).toBe('prepared');
    expect(createCall.data.preparedBy).toBe('user-1');
    expect(createCall.data.lines.create).toEqual([
      { employeeId: 'emp-1', baseSalary: 30000, advance: 0, adjustment: 0, netAmount: 30000 },
      { employeeId: 'emp-2', baseSalary: 25000, advance: 0, adjustment: 0, netAmount: 25000 },
    ]);
  });
});

describe('PayrollService.updateLine', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: PayrollService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new PayrollService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('recomputes netAmount = baseSalary - advance + adjustment', async () => {
    (prisma.payrollLine as any).findFirst.mockResolvedValue({
      id: 'line-1',
      baseSalary: { toNumber: () => 30000 },
      payrollRun: { id: 'run-1', establishmentId: 'est-1', status: 'prepared' },
    });
    await service.updateLine('est-1', 'run-1', 'line-1', { advance: 5000, adjustment: -2000 });
    expect(prisma.payrollLine.update).toHaveBeenCalledWith({
      where: { id: 'line-1' },
      data: { advance: 5000, adjustment: -2000, netAmount: 23000 },
    });
  });

  it('rejects editing a line on a run that is not "prepared"', async () => {
    (prisma.payrollLine as any).findFirst.mockResolvedValue({
      id: 'line-1',
      baseSalary: { toNumber: () => 30000 },
      payrollRun: { id: 'run-1', establishmentId: 'est-1', status: 'validated' },
    });
    await expect(service.updateLine('est-1', 'run-1', 'line-1', { advance: 0, adjustment: 0 })).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });
});

describe('PayrollService.validate / pay / cancel', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: PayrollService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new PayrollService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('validate() moves a prepared run to validated', async () => {
    (prisma.payrollRun as any).findFirst.mockResolvedValue({ id: 'run-1', establishmentId: 'est-1', status: 'prepared' });
    await service.validate('est-1', 'run-1', 'user-2');
    expect(prisma.payrollRun.update).toHaveBeenCalledWith({
      where: { id: 'run-1' },
      data: { status: 'validated', validatedBy: 'user-2', validatedAt: expect.any(Date) },
    });
  });

  it('validate() rejects a run that is not "prepared"', async () => {
    (prisma.payrollRun as any).findFirst.mockResolvedValue({ id: 'run-1', establishmentId: 'est-1', status: 'paid' });
    await expect(service.validate('est-1', 'run-1', 'user-2')).rejects.toBeInstanceOf(BadRequestException);
  });

  it('pay() creates one Expense summing all line netAmounts, linked via payrollRunId', async () => {
    (prisma.payrollRun as any).findFirst.mockResolvedValue({
      id: 'run-1',
      establishmentId: 'est-1',
      status: 'validated',
      periodEnd: new Date('2026-09-13'),
      lines: [{ netAmount: { toNumber: () => 30000 } }, { netAmount: { toNumber: () => 25000 } }],
    });
    (prisma.$transaction as any).mockImplementation((ops: any[]) => Promise.all(ops));
    await service.pay('est-1', 'run-1', 'user-3');
    expect(prisma.expense.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        establishmentId: 'est-1',
        label: 'Paiement des salaires',
        category: 'Salaires',
        amount: 55000,
        payrollRunId: 'run-1',
      }),
    });
  });

  it('pay() rejects a run that is not "validated" (never pays twice)', async () => {
    (prisma.payrollRun as any).findFirst.mockResolvedValue({ id: 'run-1', establishmentId: 'est-1', status: 'paid', lines: [] });
    await expect(service.pay('est-1', 'run-1', 'user-3')).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.expense.create).not.toHaveBeenCalled();
  });

  it('cancel() is allowed from "prepared" but not from "paid"', async () => {
    (prisma.payrollRun as any).findFirst.mockResolvedValue({ id: 'run-1', establishmentId: 'est-1', status: 'prepared' });
    await service.cancel('est-1', 'run-1');
    expect(prisma.payrollRun.update).toHaveBeenCalledWith({
      where: { id: 'run-1' },
      data: { status: 'cancelled', cancelledAt: expect.any(Date) },
    });

    (prisma.payrollRun as any).findFirst.mockResolvedValue({ id: 'run-2', establishmentId: 'est-1', status: 'paid' });
    await expect(service.cancel('est-1', 'run-2')).rejects.toBeInstanceOf(BadRequestException);
  });
});
