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
    });
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
