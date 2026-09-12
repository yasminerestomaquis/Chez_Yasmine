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
