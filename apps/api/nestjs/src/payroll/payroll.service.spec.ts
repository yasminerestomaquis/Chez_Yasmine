import { BadRequestException, NotFoundException } from '@nestjs/common';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import type { ActivityNotifierService } from '../notifications/activity-notifier.service.js';
import { PayrollService } from './payroll.service.js';

const activityNotifierMock = { notify: vi.fn() } as unknown as ActivityNotifierService;

function makePrismaMock() {
  return {
    employee: { findMany: vi.fn(), findFirst: vi.fn() },
    payrollRun: { create: vi.fn(), findFirst: vi.fn(), findMany: vi.fn(), update: vi.fn() },
    payrollLine: { update: vi.fn(), findFirst: vi.fn(), findMany: vi.fn(), create: vi.fn(), delete: vi.fn() },
    expense: { create: vi.fn(), findFirst: vi.fn(), update: vi.fn() },
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
      where: { establishmentId: 'est-1', status: 'active', salaryType: 'weekly' },
      select: { id: true, weeklySalary: true },
    });
    expect((prisma.payrollRun as any).create.mock.calls[0][0].data.periodType).toBe('weekly');
    const createCall = (prisma.payrollRun as any).create.mock.calls[0][0];
    expect(createCall.data.status).toBe('prepared');
    expect(createCall.data.preparedBy).toBe('user-1');
    expect(createCall.data.lines.create).toEqual([
      { employeeId: 'emp-1', baseSalary: 30000, advance: 0, adjustment: 0, netAmount: 30000 },
      { employeeId: 'emp-2', baseSalary: 25000, advance: 0, adjustment: 0, netAmount: 25000 },
    ]);
  });
});

describe('PayrollService.prepare (semaine omise, paie mensuelle)', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: PayrollService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new PayrollService(prisma as unknown as PrismaService, activityNotifierMock);
    (prisma.payrollRun as any).create.mockImplementation(({ data }: any) => Promise.resolve({ id: 'run-1', ...data }));
  });

  it('a monthly run only takes the active employees paid monthly', async () => {
    (prisma.employee as any).findMany.mockResolvedValue([{ id: 'emp-m', weeklySalary: { toNumber: () => 150000 } }]);
    await service.prepare('est-1', 'user-1', { periodStart: '2026-09-01', periodEnd: '2026-09-30', periodType: 'monthly' });
    expect((prisma.employee as any).findMany.mock.calls[0][0].where).toEqual({
      establishmentId: 'est-1',
      status: 'active',
      salaryType: 'monthly',
    });
    const data = (prisma.payrollRun as any).create.mock.calls[0][0].data;
    expect(data.periodType).toBe('monthly');
    expect(data.lines.create).toEqual([
      { employeeId: 'emp-m', baseSalary: 150000, advance: 0, adjustment: 0, netAmount: 150000 },
    ]);
  });

  it('a past (omitted) week can be prepared', async () => {
    (prisma.employee as any).findMany.mockResolvedValue([]);
    await service.prepare('est-1', 'user-1', { periodStart: '2026-08-17', periodEnd: '2026-08-23' });
    expect((prisma.payrollRun as any).findFirst).toHaveBeenCalledWith({
      where: {
        establishmentId: 'est-1',
        periodType: 'weekly',
        periodStart: new Date('2026-08-17'),
        status: { not: 'cancelled' },
      },
      select: { id: true },
    });
    expect((prisma.payrollRun as any).create).toHaveBeenCalledTimes(1);
  });

  it('refuses a second non-cancelled run for the same period start and type', async () => {
    (prisma.payrollRun as any).findFirst.mockResolvedValue({ id: 'existing' });
    await expect(
      service.prepare('est-1', 'user-1', { periodStart: '2026-08-17', periodEnd: '2026-08-23' }),
    ).rejects.toThrow(BadRequestException);
    expect((prisma.payrollRun as any).create).not.toHaveBeenCalled();
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

  it('allows editing a line on a validated run (historique des paies)', async () => {
    (prisma.payrollLine as any).findFirst.mockResolvedValue({
      id: 'line-1',
      baseSalary: { toNumber: () => 30000 },
      payrollRun: { id: 'run-1', establishmentId: 'est-1', status: 'validated' },
    });
    await service.updateLine('est-1', 'run-1', 'line-1', { advance: 1000, adjustment: 0 });
    expect(prisma.payrollLine.update).toHaveBeenCalledWith({
      where: { id: 'line-1' },
      data: { advance: 1000, adjustment: 0, netAmount: 29000 },
    });
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('rejects editing a line on a cancelled run', async () => {
    (prisma.payrollLine as any).findFirst.mockResolvedValue({
      id: 'line-1',
      baseSalary: { toNumber: () => 30000 },
      payrollRun: { id: 'run-1', establishmentId: 'est-1', status: 'cancelled' },
    });
    await expect(service.updateLine('est-1', 'run-1', 'line-1', { advance: 0, adjustment: 0 })).rejects.toBeInstanceOf(
      BadRequestException,
    );
    expect(prisma.payrollLine.update).not.toHaveBeenCalled();
  });

  it('on a PAID run, updates the line and the linked "Salaires" expense total in one transaction', async () => {
    (prisma.payrollLine as any).findFirst.mockResolvedValue({
      id: 'line-1',
      baseSalary: { toNumber: () => 30000 },
      payrollRun: { id: 'run-1', establishmentId: 'est-1', status: 'paid' },
    });
    const tx = makePrismaMock();
    (tx.payrollLine as any).findMany.mockResolvedValue([
      { netAmount: { toNumber: () => 28000 } },
      { netAmount: { toNumber: () => 25000 } },
    ]);
    (prisma.$transaction as any).mockImplementation((fn: any) => fn(tx));

    await service.updateLine('est-1', 'run-1', 'line-1', { advance: 2000, adjustment: 0 });

    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
    expect(prisma.payrollLine.update).not.toHaveBeenCalled();
    expect(tx.payrollLine.update).toHaveBeenCalledWith({
      where: { id: 'line-1' },
      data: { advance: 2000, adjustment: 0, netAmount: 28000 },
    });
    expect(tx.expense.update).toHaveBeenCalledWith({ where: { payrollRunId: 'run-1' }, data: { amount: 53000 } });
  });
});

describe('PayrollService.addLine / removeLine (employés de la paie)', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: PayrollService;

  const run = (status: string, employeeIds: string[] = ['emp-1']) => ({
    id: 'run-1',
    establishmentId: 'est-1',
    status,
    periodType: 'weekly',
    lines: employeeIds.map((employeeId) => ({ employeeId })),
  });
  const employee = (status = 'active', salaryType = 'weekly') => ({
    id: 'emp-2',
    status,
    salaryType,
    weeklySalary: { toNumber: () => 20000 },
  });

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new PayrollService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('addLine on a prepared run creates a line at the current weekly salary', async () => {
    (prisma.payrollRun as any).findFirst.mockResolvedValue(run('prepared'));
    (prisma.employee as any).findFirst.mockResolvedValue(employee());
    await service.addLine('est-1', 'run-1', { employeeId: 'emp-2' });
    expect(prisma.employee.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 'emp-2', establishmentId: 'est-1' } }),
    );
    expect(prisma.payrollLine.create).toHaveBeenCalledWith({
      data: { payrollRunId: 'run-1', employeeId: 'emp-2', baseSalary: 20000, advance: 0, adjustment: 0, netAmount: 20000 },
    });
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('addLine rejects a cancelled run, an unknown/inactive employee and a duplicate', async () => {
    (prisma.payrollRun as any).findFirst.mockResolvedValue(run('cancelled'));
    await expect(service.addLine('est-1', 'run-1', { employeeId: 'emp-2' })).rejects.toThrow(BadRequestException);

    (prisma.payrollRun as any).findFirst.mockResolvedValue(run('prepared'));
    (prisma.employee as any).findFirst.mockResolvedValue(null);
    await expect(service.addLine('est-1', 'run-1', { employeeId: 'emp-2' })).rejects.toThrow(NotFoundException);

    (prisma.employee as any).findFirst.mockResolvedValue(employee('inactive'));
    await expect(service.addLine('est-1', 'run-1', { employeeId: 'emp-2' })).rejects.toThrow(BadRequestException);

    (prisma.payrollRun as any).findFirst.mockResolvedValue(run('prepared', ['emp-1', 'emp-2']));
    (prisma.employee as any).findFirst.mockResolvedValue(employee());
    await expect(service.addLine('est-1', 'run-1', { employeeId: 'emp-2' })).rejects.toThrow('déjà');
    expect(prisma.payrollLine.create).not.toHaveBeenCalled();
  });

  it('addLine refuses an employee whose salary type differs from the run period type', async () => {
    (prisma.payrollRun as any).findFirst.mockResolvedValue(run('prepared'));
    (prisma.employee as any).findFirst.mockResolvedValue(employee('active', 'monthly'));
    await expect(service.addLine('est-1', 'run-1', { employeeId: 'emp-2' })).rejects.toThrow('payé au mois');
    (prisma.payrollRun as any).findFirst.mockResolvedValue({ ...run('prepared'), periodType: 'monthly' });
    (prisma.employee as any).findFirst.mockResolvedValue(employee('active', 'weekly'));
    await expect(service.addLine('est-1', 'run-1', { employeeId: 'emp-2' })).rejects.toThrow('payé à la semaine');
    expect(prisma.payrollLine.create).not.toHaveBeenCalled();
  });

  it('addLine on a PAID run also updates the linked "Salaires" expense in one transaction', async () => {
    (prisma.payrollRun as any).findFirst.mockResolvedValue(run('paid'));
    (prisma.employee as any).findFirst.mockResolvedValue(employee());
    const tx = makePrismaMock();
    (tx.payrollLine as any).findMany.mockResolvedValue([
      { netAmount: { toNumber: () => 30000 } },
      { netAmount: { toNumber: () => 20000 } },
    ]);
    (prisma.$transaction as any).mockImplementation((fn: any) => fn(tx));
    await service.addLine('est-1', 'run-1', { employeeId: 'emp-2' });
    expect(prisma.payrollLine.create).not.toHaveBeenCalled();
    expect(tx.payrollLine.create).toHaveBeenCalledTimes(1);
    expect(tx.expense.update).toHaveBeenCalledWith({ where: { payrollRunId: 'run-1' }, data: { amount: 50000 } });
  });

  const lineOf = (status: string) => ({
    id: 'line-1',
    baseSalary: { toNumber: () => 30000 },
    payrollRun: { id: 'run-1', establishmentId: 'est-1', status },
  });

  it('removeLine deletes the line of a validated run', async () => {
    (prisma.payrollLine as any).findFirst.mockResolvedValue(lineOf('validated'));
    await service.removeLine('est-1', 'run-1', 'line-1');
    expect(prisma.payrollLine.delete).toHaveBeenCalledWith({ where: { id: 'line-1' } });
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('removeLine rejects a cancelled run and a line of another establishment', async () => {
    (prisma.payrollLine as any).findFirst.mockResolvedValue(lineOf('cancelled'));
    await expect(service.removeLine('est-1', 'run-1', 'line-1')).rejects.toThrow(BadRequestException);
    (prisma.payrollLine as any).findFirst.mockResolvedValue({
      ...lineOf('prepared'),
      payrollRun: { id: 'run-1', establishmentId: 'est-2', status: 'prepared' },
    });
    await expect(service.removeLine('est-1', 'run-1', 'line-1')).rejects.toThrow(NotFoundException);
    expect(prisma.payrollLine.delete).not.toHaveBeenCalled();
  });

  it('removeLine on a PAID run recomputes the linked expense (0 when no line is left)', async () => {
    (prisma.payrollLine as any).findFirst.mockResolvedValue(lineOf('paid'));
    const tx = makePrismaMock();
    (tx.payrollLine as any).findMany.mockResolvedValue([]);
    (prisma.$transaction as any).mockImplementation((fn: any) => fn(tx));
    await service.removeLine('est-1', 'run-1', 'line-1');
    expect(tx.payrollLine.delete).toHaveBeenCalledWith({ where: { id: 'line-1' } });
    expect(tx.expense.update).toHaveBeenCalledWith({ where: { payrollRunId: 'run-1' }, data: { amount: 0 } });
  });
});

describe('PayrollService.list (période)', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: PayrollService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new PayrollService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('without bounds lists every run of the establishment', async () => {
    await service.list('est-1');
    expect((prisma.payrollRun as any).findMany.mock.calls[0][0].where).toEqual({ establishmentId: 'est-1' });
  });

  it('keeps the runs whose period overlaps [from, to]', async () => {
    await service.list('est-1', '2026-09-01', '2026-09-30');
    expect((prisma.payrollRun as any).findMany.mock.calls[0][0].where).toEqual({
      establishmentId: 'est-1',
      periodEnd: { gte: new Date('2026-09-01') },
      periodStart: { lte: new Date('2026-09-30') },
    });
  });

  it('rejects a malformed date and an inverted period', () => {
    expect(() => service.list('est-1', 'hier')).toThrow(BadRequestException);
    expect(() => service.list('est-1', '2026-09-30', '2026-09-01')).toThrow(BadRequestException);
    expect(prisma.payrollRun.findMany).not.toHaveBeenCalled();
  });
});

describe('PayrollService.updateRun (période)', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: PayrollService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new PayrollService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  const run = (status: string) => ({
    id: 'run-1',
    establishmentId: 'est-1',
    status,
    periodStart: new Date('2026-09-07'),
    periodEnd: new Date('2026-09-13'),
    lines: [],
  });

  it('updates the period of a prepared run without touching expenses', async () => {
    (prisma.payrollRun as any).findFirst.mockResolvedValue(run('prepared'));
    await service.updateRun('est-1', 'run-1', { periodStart: '2026-09-14', periodEnd: '2026-09-20' });
    expect(prisma.payrollRun.update).toHaveBeenCalledWith({
      where: { id: 'run-1' },
      data: { periodStart: new Date('2026-09-14'), periodEnd: new Date('2026-09-20') },
    });
    expect(prisma.expense.update).not.toHaveBeenCalled();
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('keeps the other bound when only one is given', async () => {
    (prisma.payrollRun as any).findFirst.mockResolvedValue(run('validated'));
    await service.updateRun('est-1', 'run-1', { periodEnd: '2026-09-15' });
    expect(prisma.payrollRun.update).toHaveBeenCalledWith({
      where: { id: 'run-1' },
      data: { periodStart: new Date('2026-09-07'), periodEnd: new Date('2026-09-15') },
    });
  });

  it('on a PAID run, moves the linked expense date to the new period end, in one transaction', async () => {
    (prisma.payrollRun as any).findFirst.mockResolvedValue(run('paid'));
    (prisma.$transaction as any).mockImplementation((ops: any[]) => Promise.all(ops));
    await service.updateRun('est-1', 'run-1', { periodStart: '2026-09-14', periodEnd: '2026-09-20' });
    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
    expect(prisma.expense.update).toHaveBeenCalledWith({
      where: { payrollRunId: 'run-1' },
      data: { expenseDate: new Date('2026-09-20') },
    });
  });

  it('rejects a period that ends before it starts', async () => {
    (prisma.payrollRun as any).findFirst.mockResolvedValue(run('prepared'));
    await expect(
      service.updateRun('est-1', 'run-1', { periodStart: '2026-09-20', periodEnd: '2026-09-14' }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.payrollRun.update).not.toHaveBeenCalled();
  });

  it('rejects a cancelled run and an unknown run', async () => {
    (prisma.payrollRun as any).findFirst.mockResolvedValue(run('cancelled'));
    await expect(service.updateRun('est-1', 'run-1', { periodEnd: '2026-09-15' })).rejects.toBeInstanceOf(
      BadRequestException,
    );
    (prisma.payrollRun as any).findFirst.mockResolvedValue(null);
    await expect(service.updateRun('est-1', 'run-x', { periodEnd: '2026-09-15' })).rejects.toBeInstanceOf(
      NotFoundException,
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
    // Atomicité : la mise à jour du statut et la création de la dépense
    // doivent transiter par le MÊME appel $transaction([...]) — deux appels
    // séparés casseraient la garantie « jamais payé sans dépense, jamais
    // de dépense sans passage à 'paid' » en cas d'échec partiel.
    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
    const [transactionOps] = (prisma.$transaction as any).mock.calls[0];
    expect(transactionOps).toHaveLength(2);
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

  it('cancel() rejects a run that is already cancelled', async () => {
    (prisma.payrollRun as any).findFirst.mockResolvedValue({ id: 'run-3', establishmentId: 'est-1', status: 'cancelled' });
    await expect(service.cancel('est-1', 'run-3')).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.payrollRun.update).not.toHaveBeenCalled();
  });
});
