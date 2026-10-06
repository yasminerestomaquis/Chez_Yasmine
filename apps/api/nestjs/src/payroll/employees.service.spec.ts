import { NotFoundException } from '@nestjs/common';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import { EmployeesService } from './employees.service.js';

function makePrismaMock() {
  return {
    employee: {
      findMany: vi.fn(),
      findFirst: vi.fn(),
      create: vi.fn(),
      updateMany: vi.fn(),
      findUniqueOrThrow: vi.fn(),
    },
    establishment: { findUniqueOrThrow: vi.fn() },
    role: { findMany: vi.fn() },
  };
}

describe('EmployeesService', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: EmployeesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new EmployeesService(prisma as unknown as PrismaService);
  });

  it('lists employees scoped to the establishment, ordered by last name', async () => {
    (prisma.employee as any).findMany.mockResolvedValue([]);
    await service.list('est-1');
    expect(prisma.employee.findMany).toHaveBeenCalledWith({
      where: { establishmentId: 'est-1' },
      orderBy: { lastName: 'asc' },
    });
  });

  it('creates an employee defaulting status to active', async () => {
    (prisma.employee as any).create.mockResolvedValue({ id: 'emp-1' });
    await service.create('est-1', {
      lastName: 'Koffi',
      firstName: 'Awa',
      phone: '0708091011',
      position: 'Cuisinière',
      hireDate: '2026-01-10',
      weeklySalary: 30000,
    });
    expect(prisma.employee.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ establishmentId: 'est-1', status: 'active' }),
    });
  });

  it('creates an employee paid weekly by default and accepts a monthly salary type', async () => {
    (prisma.employee as any).create.mockResolvedValue({ id: 'emp-1' });
    const base = { lastName: 'K', firstName: 'A', phone: '0708091011', position: 'Serveur', hireDate: '2026-01-10', weeklySalary: 1 };
    await service.create('est-1', base);
    expect((prisma.employee as any).create.mock.calls[0][0].data.salaryType).toBe('weekly');
    await service.create('est-1', { ...base, weeklySalary: 150000, salaryType: 'monthly' });
    expect((prisma.employee as any).create.mock.calls[1][0].data.salaryType).toBe('monthly');
  });

  it('lists the positions as the distinct role names (system roles + the organization\'s own), sorted', async () => {
    (prisma.establishment as any).findUniqueOrThrow.mockResolvedValue({ organizationId: 'org-1' });
    (prisma.role as any).findMany.mockResolvedValue([{ name: 'Caissier' }, { name: 'Serveur' }, { name: 'Serveur' }]);
    const positions = await service.listPositions('est-1');
    expect(positions).toEqual(['Caissier', 'Serveur']);
    expect((prisma.role as any).findMany).toHaveBeenCalledWith({
      where: { OR: [{ isSystem: true }, { organizationId: 'org-1' }] },
      select: { name: true },
      orderBy: { name: 'asc' },
    });
  });

  it('throws NotFoundException updating an employee outside the establishment', async () => {
    (prisma.employee as any).updateMany.mockResolvedValue({ count: 0 });
    await expect(service.update('est-1', 'emp-x', { position: 'Serveur' })).rejects.toBeInstanceOf(NotFoundException);
  });

  it('deactivates an employee via status update rather than deleting the row (préserve l\'historique de paie)', async () => {
    (prisma.employee as any).updateMany.mockResolvedValue({ count: 1 });
    (prisma.employee as any).findUniqueOrThrow.mockResolvedValue({ id: 'emp-1', status: 'inactive' });
    const result = await service.update('est-1', 'emp-1', { status: 'inactive' });
    expect(result.status).toBe('inactive');
  });
});
