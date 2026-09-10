import { NotFoundException } from '@nestjs/common';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import { TablesService } from './tables.service.js';

function makePrismaMock() {
  return {
    restaurantTable: {
      findMany: vi.fn(),
      create: vi.fn(),
      updateMany: vi.fn(),
      findUniqueOrThrow: vi.fn(),
      deleteMany: vi.fn(),
    },
  };
}

describe('TablesService', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: TablesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new TablesService(prisma as unknown as PrismaService);
  });

  it('lists tables scoped by establishment, ordered by zone then name', async () => {
    prisma.restaurantTable.findMany.mockResolvedValue([]);
    await service.list('est-1');
    expect(prisma.restaurantTable.findMany).toHaveBeenCalledWith({
      where: { establishmentId: 'est-1' },
      orderBy: [{ zone: 'asc' }, { name: 'asc' }],
      include: {
        orders: { where: { status: 'open' }, include: { items: true }, take: 1 },
        reservations: { where: { status: 'pending' }, orderBy: { reservedAt: 'asc' }, take: 1 },
      },
    });
  });

  it('derives guestCount and currentTotal from the open order, null when none', async () => {
    prisma.restaurantTable.findMany.mockResolvedValue([
      {
        id: 't1',
        establishmentId: 'est-1',
        name: 'T1',
        zone: null,
        status: 'occupied',
        createdAt: new Date('2026-01-01'),
        orders: [{ guestCount: 4, items: [{ quantity: 2, unitPrice: 700 }, { quantity: 1, unitPrice: 600 }] }],
        reservations: [],
      },
      {
        id: 't2',
        establishmentId: 'est-1',
        name: 'T2',
        zone: null,
        status: 'free',
        createdAt: new Date('2026-01-01'),
        orders: [],
        reservations: [],
      },
    ]);
    const result = await service.list('est-1');
    expect(result[0]).toMatchObject({ guestCount: 4, currentTotal: 2000, reservation: null });
    expect(result[1]).toMatchObject({ guestCount: null, currentTotal: null, reservation: null });
  });

  it('surfaces the pending reservation for a reserved table', async () => {
    const reservedAt = new Date('2026-09-15T19:00:00Z');
    prisma.restaurantTable.findMany.mockResolvedValue([
      {
        id: 't1',
        establishmentId: 'est-1',
        name: 'T1',
        zone: null,
        status: 'reserved',
        createdAt: new Date('2026-01-01'),
        orders: [],
        reservations: [{ id: 'r1', customerName: 'Awa', phone: '0700000000', reservedAt }],
      },
    ]);
    const result = await service.list('est-1');
    expect(result[0].reservation).toEqual({ id: 'r1', customerName: 'Awa', phone: '0700000000', reservedAt });
  });

  it('throws NotFoundException updating a table outside the establishment', async () => {
    prisma.restaurantTable.updateMany.mockResolvedValue({ count: 0 });
    await expect(service.update('est-1', 'table-x', { name: 'T1' })).rejects.toBeInstanceOf(NotFoundException);
  });

  it('throws NotFoundException removing a table outside the establishment', async () => {
    prisma.restaurantTable.deleteMany.mockResolvedValue({ count: 0 });
    await expect(service.remove('est-1', 'table-x')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('removes a table that belongs to the establishment', async () => {
    prisma.restaurantTable.deleteMany.mockResolvedValue({ count: 1 });
    await expect(service.remove('est-1', 'table-1')).resolves.toBeUndefined();
  });
});
