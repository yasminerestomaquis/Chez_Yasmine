import { NotFoundException } from '@nestjs/common';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import { CategoriesService } from './categories.service.js';

function makePrismaMock() {
  return {
    category: {
      findMany: vi.fn(),
      create: vi.fn(),
      updateMany: vi.fn(),
      deleteMany: vi.fn(),
      findUniqueOrThrow: vi.fn(),
    },
  };
}

describe('CategoriesService', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: CategoriesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new CategoriesService(prisma as unknown as PrismaService);
  });

  it('scopes list() by establishmentId', async () => {
    prisma.category.findMany.mockResolvedValue([]);
    await service.list('est-1');
    expect(prisma.category.findMany).toHaveBeenCalledWith({ where: { establishmentId: 'est-1' }, orderBy: { name: 'asc' } });
  });

  it('create() attaches the establishmentId from the route, not the body', async () => {
    prisma.category.create.mockResolvedValue({ id: 'cat-1' });
    await service.create('est-1', { name: 'Boissons' });
    expect(prisma.category.create).toHaveBeenCalledWith({ data: { establishmentId: 'est-1', name: 'Boissons' } });
  });

  it('update() throws NotFoundException when the category does not belong to the establishment', async () => {
    prisma.category.updateMany.mockResolvedValue({ count: 0 });
    await expect(service.update('est-1', 'cat-from-another-establishment', { name: 'x' })).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('remove() throws NotFoundException when the category does not belong to the establishment', async () => {
    prisma.category.deleteMany.mockResolvedValue({ count: 0 });
    await expect(service.remove('est-1', 'cat-from-another-establishment')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('remove() succeeds when the category belongs to the establishment', async () => {
    prisma.category.deleteMany.mockResolvedValue({ count: 1 });
    await expect(service.remove('est-1', 'cat-1')).resolves.toBeUndefined();
    expect(prisma.category.deleteMany).toHaveBeenCalledWith({ where: { id: 'cat-1', establishmentId: 'est-1' } });
  });
});
