import { NotFoundException } from '@nestjs/common';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import { CustomersService } from './customers.service.js';

function makePrismaMock() {
  return {
    customer: {
      findMany: vi.fn(),
      findFirst: vi.fn(),
      create: vi.fn(),
      updateMany: vi.fn(),
      findUniqueOrThrow: vi.fn(),
      deleteMany: vi.fn(),
    },
  };
}

describe('CustomersService', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: CustomersService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new CustomersService(prisma as unknown as PrismaService);
  });

  it('defaults creditLimit to 0 when creating a customer without one', async () => {
    prisma.customer.create.mockResolvedValue({ id: 'cust-1' });
    await service.create('est-1', { name: 'Awa' });
    expect(prisma.customer.create).toHaveBeenCalledWith({
      data: { establishmentId: 'est-1', name: 'Awa', phone: undefined, address: undefined, creditLimit: 0 },
    });
  });

  it('throws NotFoundException getting a customer outside the establishment', async () => {
    prisma.customer.findFirst.mockResolvedValue(null);
    await expect(service.get('est-1', 'cust-x')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('throws NotFoundException updating a customer outside the establishment', async () => {
    prisma.customer.updateMany.mockResolvedValue({ count: 0 });
    await expect(service.update('est-1', 'cust-x', { name: 'Nouveau' })).rejects.toBeInstanceOf(NotFoundException);
  });

  it('throws NotFoundException removing a customer outside the establishment', async () => {
    prisma.customer.deleteMany.mockResolvedValue({ count: 0 });
    await expect(service.remove('est-1', 'cust-x')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('removes a customer that belongs to the establishment', async () => {
    prisma.customer.deleteMany.mockResolvedValue({ count: 1 });
    await expect(service.remove('est-1', 'cust-1')).resolves.toBeUndefined();
  });
});
