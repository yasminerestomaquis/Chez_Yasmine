import { NotFoundException } from '@nestjs/common';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import { SuppliersService } from './suppliers.service.js';

function makePrismaMock() {
  return {
    supplier: { findMany: vi.fn(), create: vi.fn(), updateMany: vi.fn(), findUniqueOrThrow: vi.fn(), deleteMany: vi.fn() },
  };
}

describe('SuppliersService', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: SuppliersService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new SuppliersService(prisma as unknown as PrismaService);
  });

  it('scopes the list by establishment, ordered by name', async () => {
    prisma.supplier.findMany.mockResolvedValue([]);
    await service.list('est-1');
    expect(prisma.supplier.findMany).toHaveBeenCalledWith({ where: { establishmentId: 'est-1' }, orderBy: { name: 'asc' } });
  });

  it('throws NotFoundException updating a supplier outside the establishment', async () => {
    prisma.supplier.updateMany.mockResolvedValue({ count: 0 });
    await expect(service.update('est-1', 'sup-x', { name: 'X' })).rejects.toBeInstanceOf(NotFoundException);
  });

  it('throws NotFoundException removing a supplier outside the establishment', async () => {
    prisma.supplier.deleteMany.mockResolvedValue({ count: 0 });
    await expect(service.remove('est-1', 'sup-x')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('updates a supplier that belongs to the establishment', async () => {
    prisma.supplier.updateMany.mockResolvedValue({ count: 1 });
    prisma.supplier.findUniqueOrThrow.mockResolvedValue({ id: 'sup-1', name: 'Nouveau nom' });
    const result = await service.update('est-1', 'sup-1', { name: 'Nouveau nom' });
    expect(result).toEqual({ id: 'sup-1', name: 'Nouveau nom' });
  });
});
