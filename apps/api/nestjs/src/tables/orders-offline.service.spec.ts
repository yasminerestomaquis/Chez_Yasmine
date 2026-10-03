import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { Decimal } from '@prisma/client';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import { OrdersService } from './orders.service.js';

function makePrismaMock() {
  const prisma: Record<string, unknown> = {
    order: { create: vi.fn(), findFirst: vi.fn() },
    restaurantTable: { findFirst: vi.fn(), update: vi.fn() },
    reservation: { updateMany: vi.fn() },
    product: { findFirst: vi.fn() },
    orderItem: { create: vi.fn(), delete: vi.fn(), findFirst: vi.fn(), update: vi.fn() },
    $transaction: vi.fn(async (callback: (tx: unknown) => unknown) => callback(prisma)),
  };
  return prisma;
}

// Saisie hors ligne (phase 4, 2026-10-03) : ouverture de table et modification
// d'une addition rejouées par SyncService — idempotentes, conflits explicites.
describe('OrdersService — saisie hors ligne', () => {
  const ORDER_ID = '11111111-1111-4111-8111-111111111111';
  const ITEM_ID = '22222222-2222-4222-8222-222222222222';
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: OrdersService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new OrdersService(prisma as unknown as PrismaService);
  });

  describe('openOfflineOrder', () => {
    const input = { id: ORDER_ID, tableId: 't1', guestCount: 4 };

    it("rejoue sans rien recréer quand l'addition existe déjà (idempotent)", async () => {
      const existing = { id: ORDER_ID, items: [] };
      (prisma.order as any).findFirst.mockResolvedValue(existing);

      const result = await service.openOfflineOrder('est-1', 'user-1', input);

      expect(result).toBe(existing);
      expect(prisma.order.create).not.toHaveBeenCalled();
    });

    it("refuse une table hors de l'établissement", async () => {
      (prisma.order as any).findFirst.mockResolvedValue(null);
      (prisma.restaurantTable as any).findFirst.mockResolvedValue(null);

      await expect(service.openOfflineOrder('est-1', 'user-1', input)).rejects.toBeInstanceOf(NotFoundException);
    });

    it("crée l'addition avec l'identifiant et l'heure de saisie de l'appareil, et occupe une table libre", async () => {
      (prisma.order as any).findFirst.mockResolvedValue(null);
      (prisma.restaurantTable as any).findFirst.mockResolvedValue({ id: 't1', status: 'free' });
      (prisma.order as any).create.mockResolvedValue({ id: ORDER_ID });
      const openedAt = new Date('2026-10-02T19:00:00.000Z');

      await service.openOfflineOrder('est-1', 'user-1', input, openedAt);

      expect(prisma.order.create).toHaveBeenCalledWith({
        data: { id: ORDER_ID, establishmentId: 'est-1', tableId: 't1', serverId: 'user-1', status: 'open', guestCount: 4, openedAt },
        include: { items: true },
      });
      expect(prisma.restaurantTable.update).toHaveBeenCalledWith({ where: { id: 't1' }, data: { status: 'occupied' } });
    });

    it('table déjà occupée (ouverte entre-temps depuis un autre appareil) : addition supplémentaire, jamais une erreur', async () => {
      (prisma.order as any).findFirst.mockResolvedValue(null);
      (prisma.restaurantTable as any).findFirst.mockResolvedValue({ id: 't1', status: 'occupied' });
      (prisma.order as any).create.mockResolvedValue({ id: ORDER_ID });

      await expect(service.openOfflineOrder('est-1', 'user-1', input)).resolves.toBeDefined();

      expect(prisma.order.create).toHaveBeenCalled();
      expect(prisma.restaurantTable.update).not.toHaveBeenCalled();
    });

    it('table réservée : occupée, et sa réservation en attente passe à « seated »', async () => {
      (prisma.order as any).findFirst.mockResolvedValue(null);
      (prisma.restaurantTable as any).findFirst.mockResolvedValue({ id: 't1', status: 'reserved' });
      (prisma.order as any).create.mockResolvedValue({ id: ORDER_ID });

      await service.openOfflineOrder('est-1', 'user-1', input);

      expect(prisma.reservation.updateMany).toHaveBeenCalledWith({
        where: { tableId: 't1', status: 'pending' },
        data: { status: 'seated' },
      });
    });
  });

  describe('addItemWithId', () => {
    it("rejoue sans rien recréer quand la ligne existe déjà (idempotent), même si l'addition est entre-temps clôturée", async () => {
      const existing = { id: ITEM_ID };
      (prisma.orderItem as any).findFirst.mockResolvedValue(existing);

      const result = await service.addItemWithId('est-1', ORDER_ID, ITEM_ID, { productId: 'p1', quantity: 1 });

      expect(result).toBe(existing);
      expect(prisma.orderItem.create).not.toHaveBeenCalled();
      expect(prisma.order.findFirst).not.toHaveBeenCalled();
    });

    it("refuse d'ajouter à une addition clôturée entre-temps (conflit explicite)", async () => {
      (prisma.orderItem as any).findFirst.mockResolvedValue(null);
      (prisma.order as any).findFirst.mockResolvedValue({ id: ORDER_ID, status: 'closed' });

      await expect(
        service.addItemWithId('est-1', ORDER_ID, ITEM_ID, { productId: 'p1', quantity: 1 }),
      ).rejects.toBeInstanceOf(ConflictException);
    });

    it("crée la ligne avec l'identifiant de l'appareil, au prix catalogue, sans fusionner avec une ligne existante", async () => {
      (prisma.orderItem as any).findFirst.mockResolvedValue(null);
      (prisma.order as any).findFirst.mockResolvedValue({ id: ORDER_ID, status: 'open' });
      (prisma.product as any).findFirst.mockResolvedValue({
        id: 'p1',
        name: 'Celtia',
        salePrice: new Decimal(500),
        unitSalePrice: null,
      });
      (prisma.orderItem as any).create.mockResolvedValue({ id: ITEM_ID });

      await service.addItemWithId('est-1', ORDER_ID, ITEM_ID, { productId: 'p1', quantity: 2, unitPrice: 1 });

      expect(prisma.orderItem.create).toHaveBeenCalledWith({
        data: { id: ITEM_ID, orderId: ORDER_ID, productId: 'p1', quantity: 2, unitPrice: new Decimal(500), sellAsUnit: false },
      });
      expect(prisma.orderItem.update).not.toHaveBeenCalled();
    });

    it('applique les mêmes règles de prix que addItem : montant payé pour un prix de référence variable', async () => {
      (prisma.orderItem as any).findFirst.mockResolvedValue(null);
      (prisma.order as any).findFirst.mockResolvedValue({ id: ORDER_ID, status: 'open' });
      (prisma.product as any).findFirst.mockResolvedValue({
        id: 'p1',
        name: 'Gbêlê',
        salePrice: null,
        referenceSalePrice: new Decimal(3000),
      });
      (prisma.orderItem as any).create.mockResolvedValue({ id: ITEM_ID });

      await service.addItemWithId('est-1', ORDER_ID, ITEM_ID, { productId: 'p1', amountPaid: 200 });

      const data = (prisma.orderItem.create as any).mock.calls[0][0].data;
      expect(data.quantity).toBe(0.07);
      expect(data.unitPrice).toBeCloseTo(2857.14, 1);
    });

    it("refuse un produit hors de l'établissement", async () => {
      (prisma.orderItem as any).findFirst.mockResolvedValue(null);
      (prisma.order as any).findFirst.mockResolvedValue({ id: ORDER_ID, status: 'open' });
      (prisma.product as any).findFirst.mockResolvedValue(null);

      await expect(
        service.addItemWithId('est-1', ORDER_ID, ITEM_ID, { productId: 'p1', quantity: 1 }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('setItemQuantityIfExpected', () => {
    beforeEach(() => (prisma.order as any).findFirst.mockResolvedValue({ id: ORDER_ID, status: 'open' }));

    it("fixe la quantité quand la ligne est encore telle que l'appareil l'a vue", async () => {
      (prisma.orderItem as any).findFirst.mockResolvedValue({ id: ITEM_ID, quantity: new Decimal(2) });
      (prisma.orderItem as any).update.mockResolvedValue({ id: ITEM_ID });

      await service.setItemQuantityIfExpected('est-1', ORDER_ID, ITEM_ID, 2, 3);

      expect(prisma.orderItem.update).toHaveBeenCalledWith({ where: { id: ITEM_ID }, data: { quantity: 3 } });
    });

    it('rejeu : la ligne est déjà à la quantité visée, rien à faire', async () => {
      (prisma.orderItem as any).findFirst.mockResolvedValue({ id: ITEM_ID, quantity: new Decimal(3) });

      await service.setItemQuantityIfExpected('est-1', ORDER_ID, ITEM_ID, 2, 3);

      expect(prisma.orderItem.update).not.toHaveBeenCalled();
    });

    it('conflit explicite quand un autre appareil a modifié la ligne entre-temps — jamais écrasé en silence', async () => {
      (prisma.orderItem as any).findFirst.mockResolvedValue({ id: ITEM_ID, quantity: new Decimal(5) });

      await expect(service.setItemQuantityIfExpected('est-1', ORDER_ID, ITEM_ID, 2, 3)).rejects.toThrow(
        /modifiée entre-temps \(5 au lieu de 2\)/,
      );
      expect(prisma.orderItem.update).not.toHaveBeenCalled();
    });

    it('ligne introuvable : NotFoundException', async () => {
      (prisma.orderItem as any).findFirst.mockResolvedValue(null);

      await expect(service.setItemQuantityIfExpected('est-1', ORDER_ID, ITEM_ID, 2, 3)).rejects.toBeInstanceOf(
        NotFoundException,
      );
    });

    it('addition clôturée entre-temps : ConflictException', async () => {
      (prisma.order as any).findFirst.mockResolvedValue({ id: ORDER_ID, status: 'closed' });

      await expect(service.setItemQuantityIfExpected('est-1', ORDER_ID, ITEM_ID, 2, 3)).rejects.toBeInstanceOf(
        ConflictException,
      );
    });

    it('compare les quantités fractionnaires à la précision de la base (Gbêlê : 0,07 L)', async () => {
      (prisma.orderItem as any).findFirst.mockResolvedValue({ id: ITEM_ID, quantity: new Decimal('0.07') });
      (prisma.orderItem as any).update.mockResolvedValue({});

      await service.setItemQuantityIfExpected('est-1', ORDER_ID, ITEM_ID, 0.07000001, 0.14);

      expect(prisma.orderItem.update).toHaveBeenCalled();
    });
  });

  describe('removeItemIfExpected', () => {
    beforeEach(() => (prisma.order as any).findFirst.mockResolvedValue({ id: ORDER_ID, status: 'open' }));

    it("retire la ligne quand elle est encore telle que l'appareil l'a vue", async () => {
      (prisma.orderItem as any).findFirst.mockResolvedValue({ id: ITEM_ID, quantity: new Decimal(2) });

      const result = await service.removeItemIfExpected('est-1', ORDER_ID, ITEM_ID, 2);

      expect(result).toEqual({ removed: true });
      expect(prisma.orderItem.delete).toHaveBeenCalledWith({ where: { id: ITEM_ID } });
    });

    it('ligne déjà absente (rejeu, ou retirée ailleurs) : succès sans rien faire', async () => {
      (prisma.orderItem as any).findFirst.mockResolvedValue(null);

      const result = await service.removeItemIfExpected('est-1', ORDER_ID, ITEM_ID, 2);

      expect(result).toEqual({ removed: false });
      expect(prisma.orderItem.delete).not.toHaveBeenCalled();
    });

    it("conflit explicite quand des unités ont été ajoutées entre-temps : on ne supprime pas ce que l'appareil n'a pas vu", async () => {
      (prisma.orderItem as any).findFirst.mockResolvedValue({ id: ITEM_ID, quantity: new Decimal(4) });

      await expect(service.removeItemIfExpected('est-1', ORDER_ID, ITEM_ID, 2)).rejects.toBeInstanceOf(ConflictException);
      expect(prisma.orderItem.delete).not.toHaveBeenCalled();
    });
  });
});
