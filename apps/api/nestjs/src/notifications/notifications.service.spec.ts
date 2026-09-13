import { BadRequestException, ForbiddenException, NotFoundException } from '@nestjs/common';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import type { StockMovementsService } from '../stock/stock-movements.service.js';
import { NotificationsService } from './notifications.service.js';

function makePrismaMock() {
  const prisma: Record<string, unknown> = {
    userEstablishmentRole: { findFirst: vi.fn() },
    notification: { findMany: vi.fn(), count: vi.fn(), updateMany: vi.fn(), create: vi.fn(), findFirst: vi.fn(), deleteMany: vi.fn() },
    userProfile: { update: vi.fn().mockResolvedValue({}), findUnique: vi.fn().mockResolvedValue(null) },
  };
  return prisma;
}

function makeStockMovementsMock() {
  return { listLowStockAlerts: vi.fn() };
}

describe('NotificationsService membership check', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: NotificationsService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new NotificationsService(prisma as unknown as PrismaService, makeStockMovementsMock() as unknown as StockMovementsService);
  });

  it('rejects a user with no role on the establishment', async () => {
    (prisma.userEstablishmentRole as any).findFirst.mockResolvedValue(null);
    await expect(service.list('est-1', 'user-x')).rejects.toBeInstanceOf(ForbiddenException);
  });
});

describe('NotificationsService.list / unreadCount', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: NotificationsService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new NotificationsService(prisma as unknown as PrismaService, makeStockMovementsMock() as unknown as StockMovementsService);
    (prisma.userEstablishmentRole as any).findFirst.mockResolvedValue({ establishment: { organizationId: 'org-1' } });
  });

  it('lists notifications targeted at the user or broadcast to the whole organization', async () => {
    (prisma.notification as any).findMany.mockResolvedValue([]);
    await service.list('est-1', 'user-1');
    expect(prisma.notification.findMany).toHaveBeenCalledWith({
      where: { organizationId: 'org-1', OR: [{ userId: 'user-1' }, { userId: null }] },
      orderBy: { createdAt: 'desc' },
    });
  });

  it('records that the user just viewed the list (clears the badge from now on)', async () => {
    (prisma.notification as any).findMany.mockResolvedValue([]);
    await service.list('est-1', 'user-1');
    expect(prisma.userProfile.update).toHaveBeenCalledWith({
      where: { id: 'user-1' },
      data: { notificationsViewedAt: expect.any(Date) },
    });
  });

  it('counts unread notifications created after the last time the list was viewed', async () => {
    (prisma.userProfile as any).findUnique.mockResolvedValue({ notificationsViewedAt: new Date('2026-09-13T10:00:00Z') });
    (prisma.notification as any).count.mockResolvedValue(3);
    const result = await service.unreadCount('est-1', 'user-1');
    expect(result).toBe(3);
    expect(prisma.notification.count).toHaveBeenCalledWith({
      where: {
        organizationId: 'org-1',
        readAt: null,
        createdAt: { gt: new Date('2026-09-13T10:00:00Z') },
        OR: [{ userId: 'user-1' }, { userId: null }],
      },
    });
  });

  it('counts everything (since the beginning of time) when the user has never viewed the list', async () => {
    (prisma.userProfile as any).findUnique.mockResolvedValue({ notificationsViewedAt: null });
    (prisma.notification as any).count.mockResolvedValue(5);
    await service.unreadCount('est-1', 'user-1');
    expect(prisma.notification.count).toHaveBeenCalledWith(
      expect.objectContaining({ where: expect.objectContaining({ createdAt: { gt: new Date(0) } }) }),
    );
  });
});

describe('NotificationsService.clearAll', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: NotificationsService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new NotificationsService(prisma as unknown as PrismaService, makeStockMovementsMock() as unknown as StockMovementsService);
    (prisma.userEstablishmentRole as any).findFirst.mockResolvedValue({ establishment: { organizationId: 'org-1' } });
  });

  it('deletes every notification of the organization, targeted or broadcast', async () => {
    (prisma.notification as any).deleteMany.mockResolvedValue({ count: 7 });
    await service.clearAll('est-1', 'caller-1');
    expect(prisma.notification.deleteMany).toHaveBeenCalledWith({ where: { organizationId: 'org-1' } });
  });

  it('rejects a caller with no role on the establishment', async () => {
    (prisma.userEstablishmentRole as any).findFirst.mockResolvedValue(null);
    await expect(service.clearAll('est-1', 'user-x')).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.notification.deleteMany).not.toHaveBeenCalled();
  });
});

describe('NotificationsService.markAsRead', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: NotificationsService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new NotificationsService(prisma as unknown as PrismaService, makeStockMovementsMock() as unknown as StockMovementsService);
    (prisma.userEstablishmentRole as any).findFirst.mockResolvedValue({ establishment: { organizationId: 'org-1' } });
  });

  it('throws NotFoundException for a notification not targeted at this user (including a broadcast one)', async () => {
    (prisma.notification as any).updateMany.mockResolvedValue({ count: 0 });
    await expect(service.markAsRead('est-1', 'user-1', 'notif-1')).rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.notification.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 'notif-1', userId: 'user-1' } }),
    );
  });

  it('marks a targeted notification read', async () => {
    (prisma.notification as any).updateMany.mockResolvedValue({ count: 1 });
    await expect(service.markAsRead('est-1', 'user-1', 'notif-1')).resolves.toBeUndefined();
  });
});

describe('NotificationsService.broadcast', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: NotificationsService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new NotificationsService(prisma as unknown as PrismaService, makeStockMovementsMock() as unknown as StockMovementsService);
    (prisma.userEstablishmentRole as any).findFirst.mockResolvedValue({ establishment: { organizationId: 'org-1' } });
  });

  it('creates an org-wide notification when no userId is given', async () => {
    (prisma.notification as any).create.mockResolvedValue({ id: 'notif-1' });
    await service.broadcast('est-1', 'caller-1', { title: 'Fermeture demain' });
    expect(prisma.notification.create).toHaveBeenCalledWith({
      data: { organizationId: 'org-1', userId: undefined, title: 'Fermeture demain', body: undefined },
    });
  });

  it('rejects a target user outside the organization', async () => {
    (prisma.userEstablishmentRole as any).findFirst
      .mockResolvedValueOnce({ establishment: { organizationId: 'org-1' } }) // caller membership
      .mockResolvedValueOnce(null); // target membership
    await expect(service.broadcast('est-1', 'caller-1', { title: 'Salut', userId: 'user-x' })).rejects.toBeInstanceOf(
      BadRequestException,
    );
    expect(prisma.notification.create).not.toHaveBeenCalled();
  });
});

describe('NotificationsService.generateLowStockAlerts', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let stockMovements: ReturnType<typeof makeStockMovementsMock>;
  let service: NotificationsService;

  beforeEach(() => {
    prisma = makePrismaMock();
    stockMovements = makeStockMovementsMock();
    service = new NotificationsService(prisma as unknown as PrismaService, stockMovements as unknown as StockMovementsService);
    (prisma.userEstablishmentRole as any).findFirst.mockResolvedValue({ establishment: { organizationId: 'org-1' } });
  });

  it('creates one notification per low-stock product', async () => {
    stockMovements.listLowStockAlerts.mockResolvedValue([{ id: 'p1', name: 'Bière', stockQuantity: 2, minStock: 5 }]);
    (prisma.notification as any).findFirst.mockResolvedValue(null);
    (prisma.notification as any).create.mockResolvedValue({ id: 'notif-1' });

    const result = await service.generateLowStockAlerts('est-1', 'caller-1');

    expect(result).toHaveLength(1);
    expect(prisma.notification.create).toHaveBeenCalledWith({
      data: { organizationId: 'org-1', title: 'Stock bas : Bière', body: 'Quantité actuelle : 2 (seuil : 5)' },
    });
  });

  it('skips a product that already has an unread low-stock notification', async () => {
    stockMovements.listLowStockAlerts.mockResolvedValue([{ id: 'p1', name: 'Bière', stockQuantity: 2, minStock: 5 }]);
    (prisma.notification as any).findFirst.mockResolvedValue({ id: 'existing' });

    const result = await service.generateLowStockAlerts('est-1', 'caller-1');

    expect(result).toHaveLength(0);
    expect(prisma.notification.create).not.toHaveBeenCalled();
  });
});
