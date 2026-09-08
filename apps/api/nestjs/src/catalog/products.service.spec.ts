import { BadRequestException, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
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

  it('create() rejects a missing salePrice for a category without variable pricing', async () => {
    await expect(service.create('est-1', { name: 'Bière' })).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.product.create).not.toHaveBeenCalled();
  });

  describe('variable-pricing categories (ex. Poulets, Poissons, Plats africains)', () => {
    it('create() allows a missing salePrice', async () => {
      prisma.category.findFirst.mockResolvedValue({ id: 'cat-poulets', hasVariablePricing: true });
      prisma.product.create.mockResolvedValue({ id: 'prod-1' });

      await expect(service.create('est-1', { name: 'Poulet braisé', categoryId: 'cat-poulets' })).resolves.toEqual({
        id: 'prod-1',
      });
    });

    it('create() forces purchase/sale price to null even if the client sent values', async () => {
      prisma.category.findFirst.mockResolvedValue({ id: 'cat-poulets', hasVariablePricing: true });
      prisma.product.create.mockResolvedValue({ id: 'prod-1' });

      await service.create('est-1', {
        name: 'Poulet braisé',
        categoryId: 'cat-poulets',
        purchasePrice: 1000, // ignoré : jamais fixé côté catalogue pour cette catégorie
        salePrice: 2000,
      });

      expect(prisma.product.create).toHaveBeenCalledWith({
        data: expect.objectContaining({ purchasePrice: null, salePrice: null }),
      });
    });

    it('update() forces purchase/sale price to null when the (new or existing) category has variable pricing', async () => {
      prisma.product.findFirst.mockResolvedValue({ id: 'prod-1', categoryId: 'cat-poulets', salePrice: null });
      prisma.category.findFirst.mockResolvedValue({ id: 'cat-poulets', hasVariablePricing: true });
      prisma.product.updateMany.mockResolvedValue({ count: 1 });

      await service.update('est-1', 'prod-1', { salePrice: 2000 });

      expect(prisma.product.updateMany).toHaveBeenCalledWith({
        where: { id: 'prod-1', establishmentId: 'est-1' },
        data: expect.objectContaining({ purchasePrice: null, salePrice: null }),
      });
    });
  });

  it('update() rejects clearing the sale price of a fixed-price product without providing a new one', async () => {
    prisma.product.findFirst.mockResolvedValue({ id: 'prod-1', categoryId: null, salePrice: null });
    await expect(service.update('est-1', 'prod-1', { name: 'Bière renommée' })).rejects.toBeInstanceOf(
      BadRequestException,
    );
    expect(prisma.product.updateMany).not.toHaveBeenCalled();
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

  describe('remove()', () => {
    it('deletes the product physically when nothing references it', async () => {
      prisma.product.deleteMany.mockResolvedValue({ count: 1 });
      const result = await service.remove('est-1', 'prod-1');
      expect(result).toEqual({ softDeleted: false });
      expect(prisma.product.updateMany).not.toHaveBeenCalled();
    });

    it('throws NotFoundException when the product does not belong to the establishment', async () => {
      prisma.product.deleteMany.mockResolvedValue({ count: 0 });
      await expect(service.remove('est-1', 'prod-from-another-establishment')).rejects.toBeInstanceOf(NotFoundException);
    });

    it('falls back to deactivating the product when it is referenced by historical records (FK violation)', async () => {
      prisma.product.deleteMany.mockRejectedValue(
        new Prisma.PrismaClientKnownRequestError('Foreign key constraint failed', { code: 'P2003', clientVersion: 'test' }),
      );
      prisma.product.updateMany.mockResolvedValue({ count: 1 });

      const result = await service.remove('est-1', 'prod-1');

      expect(result).toEqual({ softDeleted: true });
      expect(prisma.product.updateMany).toHaveBeenCalledWith({
        where: { id: 'prod-1', establishmentId: 'est-1' },
        data: { status: 'inactive' },
      });
    });

    it('rethrows other Prisma errors instead of silently deactivating', async () => {
      prisma.product.deleteMany.mockRejectedValue(new Error('connection lost'));
      await expect(service.remove('est-1', 'prod-1')).rejects.toThrow('connection lost');
      expect(prisma.product.updateMany).not.toHaveBeenCalled();
    });
  });
});
