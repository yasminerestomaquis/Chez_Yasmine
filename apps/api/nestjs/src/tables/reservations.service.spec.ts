import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import { ReservationsService } from './reservations.service.js';

function makePrismaMock() {
  const prisma: Record<string, unknown> = {
    restaurantTable: { findFirst: vi.fn(), update: vi.fn() },
    reservation: { create: vi.fn(), findFirst: vi.fn(), update: vi.fn() },
    $transaction: vi.fn(async (callback: (tx: unknown) => unknown) => callback(prisma)),
  };
  return prisma;
}

describe('ReservationsService.create', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: ReservationsService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new ReservationsService(prisma as unknown as PrismaService);
  });

  it('throws NotFoundException for a table outside the establishment', async () => {
    (prisma.restaurantTable as any).findFirst.mockResolvedValue(null);
    await expect(
      service.create('est-1', 'table-x', { reservedAt: '2026-09-15T19:00:00Z' }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('rejects reserving a table that is not free', async () => {
    (prisma.restaurantTable as any).findFirst.mockResolvedValue({ id: 't1', status: 'occupied' });
    await expect(
      service.create('est-1', 't1', { reservedAt: '2026-09-15T19:00:00Z' }),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it('creates a pending reservation and marks the table reserved', async () => {
    (prisma.restaurantTable as any).findFirst.mockResolvedValue({ id: 't1', status: 'free' });
    (prisma.reservation as any).create.mockResolvedValue({ id: 'r1' });

    await service.create('est-1', 't1', { customerName: 'Awa', phone: '0700000000', reservedAt: '2026-09-15T19:00:00Z' });

    expect(prisma.reservation.create).toHaveBeenCalledWith({
      data: { tableId: 't1', customerName: 'Awa', phone: '0700000000', reservedAt: new Date('2026-09-15T19:00:00Z'), status: 'pending' },
    });
    expect(prisma.restaurantTable.update).toHaveBeenCalledWith({ where: { id: 't1' }, data: { status: 'reserved' } });
  });
});

describe('ReservationsService.cancel', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: ReservationsService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new ReservationsService(prisma as unknown as PrismaService);
  });

  it('throws NotFoundException for a reservation outside the establishment', async () => {
    (prisma.reservation as any).findFirst.mockResolvedValue(null);
    await expect(service.cancel('est-1', 'r-x')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('rejects cancelling an already-resolved reservation', async () => {
    (prisma.reservation as any).findFirst.mockResolvedValue({
      id: 'r1',
      status: 'seated',
      tableId: 't1',
      table: { status: 'occupied' },
    });
    await expect(service.cancel('est-1', 'r1')).rejects.toBeInstanceOf(BadRequestException);
  });

  it('cancels a pending reservation and frees the table', async () => {
    (prisma.reservation as any).findFirst.mockResolvedValue({
      id: 'r1',
      status: 'pending',
      tableId: 't1',
      table: { status: 'reserved' },
    });
    (prisma.reservation as any).update.mockResolvedValue({ id: 'r1', status: 'cancelled' });

    await service.cancel('est-1', 'r1');

    expect(prisma.reservation.update).toHaveBeenCalledWith({ where: { id: 'r1' }, data: { status: 'cancelled' } });
    expect(prisma.restaurantTable.update).toHaveBeenCalledWith({ where: { id: 't1' }, data: { status: 'free' } });
  });

  it('does not touch the table if it was already opened in the meantime', async () => {
    (prisma.reservation as any).findFirst.mockResolvedValue({
      id: 'r1',
      status: 'pending',
      tableId: 't1',
      table: { status: 'occupied' },
    });
    (prisma.reservation as any).update.mockResolvedValue({ id: 'r1', status: 'cancelled' });

    await service.cancel('est-1', 'r1');

    expect(prisma.restaurantTable.update).not.toHaveBeenCalled();
  });
});
