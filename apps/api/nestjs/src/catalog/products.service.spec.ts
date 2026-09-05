import { BadRequestException, NotFoundException } from '@nestjs/common';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import { ProductsService } from './products.service.js';

function makePrismaMock() {
  return {
    product: {
      findMany: vi.fn(),
      findFirst: vi.fn(),
      create: vi.fn(),
      updateMany: vi.fn(),
      deleteMany: vi.fn(),
    },
    category: { findFirst: vi.fn() },
    supplier: { findFirst: vi.fn() },
  };
}

describe('ProductsService', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: ProductsService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new ProductsService(prisma as unknown as PrismaService);
  });

  it('rejects creating a product with a categoryId from another establishment', async () => {
    prisma.category.findFirst.mockResolvedValue(null);
    await expect(
      service.create('est-1', { name: 'Bière', salePrice: 1000, categoryId: 'cat-from-another-establishment' }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.category.findFirst).toHaveBeenCalledWith({
      where: { id: 'cat-from-another-establishment', establishmentId: 'est-1' },
    });
    expect(prisma.product.create).not.toHaveBeenCalled();
  });

  it('rejects creating a product with a supplierId from another establishment', async () => {
    prisma.supplier.findFirst.mockResolvedValue(null);
    await expect(
      service.create('est-1', { name: 'Bière', salePrice: 1000, supplierId: 'sup-from-another-establishment' }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.product.create).not.toHaveBeenCalled();
  });

  it('creates a product when references are omitted', async () => {
    prisma.product.create.mockResolvedValue({ id: 'prod-1' });
    await service.create('est-1', { name: 'Bière', salePrice: 1000 });
    expect(prisma.product.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ establishmentId: 'est-1', name: 'Bière', salePrice: 1000, stockQuantity: 0, status: 'active' }),
    });
  });

  it('get() throws NotFoundException when the product does not belong to the establishment', async () => {
    prisma.product.findFirst.mockResolvedValue(null);
    await expect(service.get('est-1', 'prod-from-another-establishment')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('update() throws NotFoundException when the product does not belong to the establishment', async () => {
    prisma.product.updateMany.mockResolvedValue({ count: 0 });
    await expect(service.update('est-1', 'prod-from-another-establishment', { name: 'x' })).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });
});
