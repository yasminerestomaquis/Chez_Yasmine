import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { AuthorizationService } from '../auth/authorization.service.js';
import type { PrismaService } from '../prisma/prisma.service.js';
import type { CashService } from '../cash/cash.service.js';
import type { ExpensesService } from '../expenses/expenses.service.js';
import type { LossesService } from '../losses/losses.service.js';
import type { SalesService } from '../pos/sales.service.js';
import type { PurchasesService } from '../purchasing/purchases.service.js';
import type { StockMovementsService } from '../stock/stock-movements.service.js';
import type { OrdersService } from '../tables/orders.service.js';
import { resolveCapturedAt, SyncService } from './sync.service.js';

function makePrismaMock() {
  return {
    syncOperation: { findUnique: vi.fn(), upsert: vi.fn(), update: vi.fn() },
  };
}

describe('SyncService.processBatch', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let authorization: { hasAllPermissions: ReturnType<typeof vi.fn> };
  let sales: { create: ReturnType<typeof vi.fn> };
  let stockMovements: { create: ReturnType<typeof vi.fn> };
  let expenses: { create: ReturnType<typeof vi.fn> };
  let losses: { create: ReturnType<typeof vi.fn> };
  let purchases: { create: ReturnType<typeof vi.fn> };
  let cash: { close: ReturnType<typeof vi.fn> };
  let orders: {
    openOfflineOrder: ReturnType<typeof vi.fn>;
    addItemWithId: ReturnType<typeof vi.fn>;
    setItemQuantityIfExpected: ReturnType<typeof vi.fn>;
    removeItemIfExpected: ReturnType<typeof vi.fn>;
  };
  let service: SyncService;

  beforeEach(() => {
    prisma = makePrismaMock();
    authorization = { hasAllPermissions: vi.fn().mockResolvedValue(true) };
    sales = { create: vi.fn() };
    stockMovements = { create: vi.fn() };
    expenses = { create: vi.fn() };
    losses = { create: vi.fn() };
    purchases = { create: vi.fn() };
    cash = { close: vi.fn() };
    orders = {
      openOfflineOrder: vi.fn(),
      addItemWithId: vi.fn(),
      setItemQuantityIfExpected: vi.fn(),
      removeItemIfExpected: vi.fn(),
    };
    service = new SyncService(
      prisma as unknown as PrismaService,
      authorization as unknown as AuthorizationService,
      sales as unknown as SalesService,
      stockMovements as unknown as StockMovementsService,
      expenses as unknown as ExpensesService,
      losses as unknown as LossesService,
      purchases as unknown as PurchasesService,
      cash as unknown as CashService,
      orders as unknown as OrdersService,
    );
  });

  it('returns SYNCED immediately for an operation already synced, without dispatching it again', async () => {
    prisma.syncOperation.findUnique.mockResolvedValue({ id: 'op-1', status: 'SYNCED', payload: { id: 'sale-1' } });

    const [result] = await service.processBatch('est-1', 'user-1', [
      { id: 'op-1', entityType: 'sale', deviceId: 'device-1', payload: { items: [] } },
    ]);

    expect(result).toEqual({ id: 'op-1', status: 'SYNCED', result: { id: 'sale-1' } });
    expect(sales.create).not.toHaveBeenCalled();
  });

  it('rejects an operation the user lacks the permission for, without dispatching it', async () => {
    prisma.syncOperation.findUnique.mockResolvedValue(null);
    authorization.hasAllPermissions.mockResolvedValue(false);

    const [result] = await service.processBatch('est-1', 'user-1', [
      { id: 'op-1', entityType: 'stock_movement', deviceId: 'device-1', payload: { productId: 'p1', type: 'in', quantity: 1 } },
    ]);

    expect(result.status).toBe('FAILED');
    expect(stockMovements.create).not.toHaveBeenCalled();
  });

  it('dispatches a sale operation with the operation id reused as the sale id, and marks it SYNCED', async () => {
    prisma.syncOperation.findUnique.mockResolvedValue(null);
    sales.create.mockResolvedValue({ id: 'op-1', total: 1000 });

    const [result] = await service.processBatch('est-1', 'user-1', [
      {
        id: 'op-1',
        entityType: 'sale',
        deviceId: 'device-1',
        payload: { items: [{ productId: 'p1', quantity: 1 }], payments: [{ method: 'cash', amount: 1000 }] },
      },
    ]);

    expect(sales.create).toHaveBeenCalledWith(
      'est-1',
      'user-1',
      expect.objectContaining({ id: 'op-1', items: [{ productId: 'p1', quantity: 1 }] }),
    );
    expect(result.status).toBe('SYNCED');
    expect(prisma.syncOperation.update).toHaveBeenCalledWith({ where: { id: 'op-1' }, data: { status: 'SYNCED' } });
  });

  it('dispatches a stock_movement operation, pulling productId out of the payload', async () => {
    prisma.syncOperation.findUnique.mockResolvedValue(null);
    stockMovements.create.mockResolvedValue({ id: 'op-2' });

    await service.processBatch('est-1', 'user-1', [
      { id: 'op-2', entityType: 'stock_movement', deviceId: 'device-1', payload: { productId: 'p1', type: 'in', quantity: 5 } },
    ]);

    expect(stockMovements.create).toHaveBeenCalledWith(
      'est-1',
      'p1',
      'user-1',
      expect.objectContaining({ id: 'op-2', type: 'in', quantity: 5 }),
      { createdAt: undefined },
    );
  });

  it('marks an operation CONFLICT (not SYNCED) when the underlying service throws — e.g. insufficient stock', async () => {
    prisma.syncOperation.findUnique.mockResolvedValue(null);
    stockMovements.create.mockRejectedValue(new Error('stock insuffisant pour ce mouvement'));

    const [result] = await service.processBatch('est-1', 'user-1', [
      { id: 'op-3', entityType: 'stock_movement', deviceId: 'device-1', payload: { productId: 'p1', type: 'out', quantity: 99 } },
    ]);

    expect(result.status).toBe('CONFLICT');
    expect(result.error).toContain('stock insuffisant');
  });

  it('dispatches an expense operation with the operation id reused as the expense id, and marks it SYNCED', async () => {
    prisma.syncOperation.findUnique.mockResolvedValue(null);
    expenses.create.mockResolvedValue({ id: 'op-6', label: 'Eau' });

    const [result] = await service.processBatch('est-1', 'user-1', [
      { id: 'op-6', entityType: 'expense', deviceId: 'device-1', payload: { label: 'Eau', amount: 5000 } },
    ]);

    expect(expenses.create).toHaveBeenCalledWith(
      'est-1',
      'user-1',
      expect.objectContaining({ id: 'op-6', label: 'Eau', amount: 5000 }),
    );
    expect(result.status).toBe('SYNCED');
  });

  it('dispatches a loss operation with the operation id reused as the loss id, and marks it SYNCED', async () => {
    prisma.syncOperation.findUnique.mockResolvedValue(null);
    losses.create.mockResolvedValue({ id: 'op-7' });

    const [result] = await service.processBatch('est-1', 'user-1', [
      { id: 'op-7', entityType: 'loss', deviceId: 'device-1', payload: { productId: 'p1', quantity: 2, reason: 'Casse' } },
    ]);

    expect(losses.create).toHaveBeenCalledWith(
      'est-1',
      'user-1',
      expect.objectContaining({ id: 'op-7', productId: 'p1', quantity: 2 }),
    );
    expect(result.status).toBe('SYNCED');
  });

  it('dispatches a purchase operation with the operation id reused as the purchase id, and marks it SYNCED', async () => {
    prisma.syncOperation.findUnique.mockResolvedValue(null);
    purchases.create.mockResolvedValue({ id: 'op-8' });

    const [result] = await service.processBatch('est-1', 'user-1', [
      {
        id: 'op-8',
        entityType: 'purchase',
        deviceId: 'device-1',
        payload: { orderNumber: 12, items: [{ productId: 'p1', casesOrdered: 2 }] },
      },
    ]);

    expect(purchases.create).toHaveBeenCalledWith('est-1', 'user-1', expect.objectContaining({ id: 'op-8', orderNumber: 12 }));
    expect(result.status).toBe('SYNCED');
  });

  it('dispatches a cash_closing operation with the operation id reused as the closing id, and marks it SYNCED', async () => {
    prisma.syncOperation.findUnique.mockResolvedValue(null);
    cash.close.mockResolvedValue({ id: 'op-9' });

    const [result] = await service.processBatch('est-1', 'user-1', [
      {
        id: 'op-9',
        entityType: 'cash_closing',
        deviceId: 'device-1',
        payload: { openedAt: '2026-09-13T08:00:00.000Z', countedAmount: 5000 },
      },
    ]);

    expect(cash.close).toHaveBeenCalledWith(
      'est-1',
      'user-1',
      expect.objectContaining({ id: 'op-9', countedAmount: 5000 }),
      { closedAt: undefined },
    );
    expect(result.status).toBe('SYNCED');
  });

  it('processes every operation in the batch even if one of them fails', async () => {
    prisma.syncOperation.findUnique.mockResolvedValue(null);
    sales.create.mockRejectedValueOnce(new Error('paiement incomplet')).mockResolvedValueOnce({ id: 'op-5' });

    const results = await service.processBatch('est-1', 'user-1', [
      { id: 'op-4', entityType: 'sale', deviceId: 'device-1', payload: { items: [], payments: [] } },
      { id: 'op-5', entityType: 'sale', deviceId: 'device-1', payload: { items: [], payments: [] } },
    ]);

    expect(results.map((r) => r.status)).toEqual(['CONFLICT', 'SYNCED']);
  });

  describe('opérations sur les additions saisies hors ligne (phase 4, 2026-10-03)', () => {
    const ORDER = '11111111-1111-4111-8111-111111111111';
    const ITEM = '22222222-2222-4222-8222-222222222222';
    const TABLE = '33333333-3333-4333-8333-333333333333';
    const PRODUCT = '44444444-4444-4444-8444-444444444444';

    beforeEach(() => prisma.syncOperation.findUnique.mockResolvedValue(null));

    it("order_open : l'identifiant de l'opération devient celui de l'addition, avec l'heure de saisie comme ouverture", async () => {
      orders.openOfflineOrder.mockResolvedValue({ id: ORDER });
      const capturedAt = new Date(Date.now() - 3600_000).toISOString();

      const [result] = await service.processBatch('est-1', 'user-1', [
        { id: ORDER, entityType: 'order_open', deviceId: 'd', payload: { tableId: TABLE, guestCount: 3 }, capturedAt },
      ]);

      expect(orders.openOfflineOrder).toHaveBeenCalledWith(
        'est-1',
        'user-1',
        { id: ORDER, tableId: TABLE, guestCount: 3 },
        new Date(capturedAt),
      );
      expect(result.status).toBe('SYNCED');
    });

    it("order_item_add : relaie la ligne avec son identifiant et les champs de prix, sans le nom d'affichage", async () => {
      orders.addItemWithId.mockResolvedValue({ id: ITEM });

      await service.processBatch('est-1', 'user-1', [
        {
          id: 'op-1',
          entityType: 'order_item_add',
          deviceId: 'd',
          payload: {
            orderId: ORDER,
            itemId: ITEM,
            productId: PRODUCT,
            quantity: 2,
            sellAsUnit: true,
            productName: 'Celtia',
          },
        },
      ]);

      expect(orders.addItemWithId).toHaveBeenCalledWith('est-1', ORDER, ITEM, {
        productId: PRODUCT,
        quantity: 2,
        unitPrice: undefined,
        amountPaid: undefined,
        sellAsUnit: true,
      });
    });

    it('order_item_set et order_item_remove : relaient la quantité vue et la quantité visée', async () => {
      orders.setItemQuantityIfExpected.mockResolvedValue({});
      orders.removeItemIfExpected.mockResolvedValue({ removed: true });

      const results = await service.processBatch('est-1', 'user-1', [
        {
          id: 'op-1',
          entityType: 'order_item_set',
          deviceId: 'd',
          payload: { orderId: ORDER, itemId: ITEM, expectedQuantity: 2, quantity: 3 },
        },
        {
          id: 'op-2',
          entityType: 'order_item_remove',
          deviceId: 'd',
          payload: { orderId: ORDER, itemId: ITEM, expectedQuantity: 3 },
        },
      ]);

      expect(orders.setItemQuantityIfExpected).toHaveBeenCalledWith('est-1', ORDER, ITEM, 2, 3);
      expect(orders.removeItemIfExpected).toHaveBeenCalledWith('est-1', ORDER, ITEM, 3);
      expect(results.map((r) => r.status)).toEqual(['SYNCED', 'SYNCED']);
    });

    it('exige tables.manage, comme les routes HTTP des additions', async () => {
      authorization.hasAllPermissions.mockResolvedValue(false);

      const [result] = await service.processBatch('est-1', 'user-1', [
        { id: ORDER, entityType: 'order_open', deviceId: 'd', payload: { tableId: TABLE } },
      ]);

      expect(authorization.hasAllPermissions).toHaveBeenCalledWith('user-1', 'est-1', ['tables.manage']);
      expect(result.status).toBe('FAILED');
      expect(orders.openOfflineOrder).not.toHaveBeenCalled();
    });

    it('un conflit de quantité détecté par le serveur marque l’opération CONFLICT avec son motif (jamais écrasé)', async () => {
      orders.setItemQuantityIfExpected.mockRejectedValue(new Error('La quantité de cet article a été modifiée entre-temps'));

      const [result] = await service.processBatch('est-1', 'user-1', [
        {
          id: 'op-1',
          entityType: 'order_item_set',
          deviceId: 'd',
          payload: { orderId: ORDER, itemId: ITEM, expectedQuantity: 2, quantity: 3 },
        },
      ]);

      expect(result.status).toBe('CONFLICT');
      expect(result.error).toContain('modifiée entre-temps');
    });

    it('une charge utile invalide (identifiant absent ou mal formé) est rejetée avant tout appel au service', async () => {
      const results = await service.processBatch('est-1', 'user-1', [
        { id: 'op-1', entityType: 'order_open', deviceId: 'd', payload: {} },
        { id: 'op-2', entityType: 'order_item_set', deviceId: 'd', payload: { orderId: 'pas-un-uuid', itemId: ITEM, expectedQuantity: 1, quantity: 2 } },
        { id: 'op-3', entityType: 'order_item_set', deviceId: 'd', payload: { orderId: ORDER, itemId: ITEM, expectedQuantity: 'x', quantity: 2 } },
      ]);

      expect(results.map((r) => r.status)).toEqual(['CONFLICT', 'CONFLICT', 'CONFLICT']);
      expect(results[0].error).toContain('tableId');
      expect(orders.openOfflineOrder).not.toHaveBeenCalled();
      expect(orders.setItemQuantityIfExpected).not.toHaveBeenCalled();
    });

    it('les opérations arrivent dans l’ordre de la file : ouverture, ajout, quantité, puis encaissement de la même addition', async () => {
      const calls: string[] = [];
      orders.openOfflineOrder.mockImplementation(async () => calls.push('open'));
      orders.addItemWithId.mockImplementation(async () => calls.push('add'));
      orders.setItemQuantityIfExpected.mockImplementation(async () => calls.push('set'));
      sales.create.mockImplementation(async () => calls.push('sale'));

      await service.processBatch('est-1', 'user-1', [
        { id: ORDER, entityType: 'order_open', deviceId: 'd', payload: { tableId: TABLE } },
        { id: 'op-2', entityType: 'order_item_add', deviceId: 'd', payload: { orderId: ORDER, itemId: ITEM, productId: PRODUCT, quantity: 1 } },
        { id: 'op-3', entityType: 'order_item_set', deviceId: 'd', payload: { orderId: ORDER, itemId: ITEM, expectedQuantity: 1, quantity: 2 } },
        { id: 'op-4', entityType: 'sale', deviceId: 'd', payload: { orderId: ORDER, items: [], payments: [] } },
      ]);

      expect(calls).toEqual(['open', 'add', 'set', 'sale']);
    });
  });

  describe("capturedAt (heure de saisie sur l'appareil, 2026-10-03)", () => {
    const minutesAgo = (m: number) => new Date(Date.now() - m * 60_000).toISOString();

    beforeEach(() => prisma.syncOperation.findUnique.mockResolvedValue(null));

    it("une vente saisie hors ligne reçoit l'heure de saisie comme createdAt", async () => {
      sales.create.mockResolvedValue({ id: 'op-1' });
      const capturedAt = minutesAgo(90);

      await service.processBatch('est-1', 'user-1', [
        { id: 'op-1', entityType: 'sale', deviceId: 'd', payload: { items: [], payments: [] }, capturedAt },
      ]);

      expect(sales.create).toHaveBeenCalledWith('est-1', 'user-1', expect.objectContaining({ id: 'op-1', createdAt: capturedAt }));
    });

    it('une vente sans heure de saisie ne reçoit aucun createdAt (horodatage serveur)', async () => {
      sales.create.mockResolvedValue({ id: 'op-1' });

      await service.processBatch('est-1', 'user-1', [
        { id: 'op-1', entityType: 'sale', deviceId: 'd', payload: { items: [], payments: [] } },
      ]);

      expect(sales.create.mock.calls[0][2]).not.toHaveProperty('createdAt');
    });

    it("la date choisie par le caissier prime sur l'heure de saisie quand il porte pos.set_date", async () => {
      sales.create.mockResolvedValue({ id: 'op-1' });
      const chosen = '2026-09-28T10:00:00.000Z';

      await service.processBatch('est-1', 'user-1', [
        {
          id: 'op-1',
          entityType: 'sale',
          deviceId: 'd',
          payload: { items: [], payments: [], createdAt: chosen },
          capturedAt: minutesAgo(5),
        },
      ]);

      expect(authorization.hasAllPermissions).toHaveBeenCalledWith('user-1', 'est-1', ['pos.set_date']);
      expect(sales.create).toHaveBeenCalledWith('est-1', 'user-1', expect.objectContaining({ createdAt: chosen }));
    });

    it("sans pos.set_date, la date choisie est ignorée au profit de l'heure de saisie réelle", async () => {
      sales.create.mockResolvedValue({ id: 'op-1' });
      authorization.hasAllPermissions.mockImplementation(async (_u: string, _e: string, codes: string[]) => !codes.includes('pos.set_date'));
      const capturedAt = minutesAgo(5);

      await service.processBatch('est-1', 'user-1', [
        {
          id: 'op-1',
          entityType: 'sale',
          deviceId: 'd',
          payload: { items: [], payments: [], createdAt: '2026-01-01T00:00:00.000Z' },
          capturedAt,
        },
      ]);

      expect(sales.create).toHaveBeenCalledWith('est-1', 'user-1', expect.objectContaining({ createdAt: capturedAt }));
    });

    it("un mouvement de stock reçoit l'heure de saisie (ordre FIFO des lots)", async () => {
      stockMovements.create.mockResolvedValue({ id: 'op-2' });
      const capturedAt = minutesAgo(120);

      await service.processBatch('est-1', 'user-1', [
        { id: 'op-2', entityType: 'stock_movement', deviceId: 'd', payload: { productId: 'p1', type: 'in', quantity: 5 }, capturedAt },
      ]);

      expect(stockMovements.create).toHaveBeenCalledWith('est-1', 'p1', 'user-1', expect.anything(), { createdAt: new Date(capturedAt) });
    });

    it("une perte reçoit l'heure de saisie, sans exiger losses.edit", async () => {
      losses.create.mockResolvedValue({ id: 'op-7' });
      const capturedAt = minutesAgo(30);

      await service.processBatch('est-1', 'user-1', [
        { id: 'op-7', entityType: 'loss', deviceId: 'd', payload: { productId: 'p1', quantity: 1 }, capturedAt },
      ]);

      expect(authorization.hasAllPermissions).not.toHaveBeenCalledWith('user-1', 'est-1', ['losses.edit']);
      expect(losses.create).toHaveBeenCalledWith('est-1', 'user-1', expect.objectContaining({ createdAt: capturedAt }));
    });

    it("une clôture de caisse est arrêtée à l'heure de saisie, pas à celle de la synchronisation", async () => {
      cash.close.mockResolvedValue({ id: 'op-9' });
      const capturedAt = minutesAgo(45);

      await service.processBatch('est-1', 'user-1', [
        {
          id: 'op-9',
          entityType: 'cash_closing',
          deviceId: 'd',
          payload: { openedAt: minutesAgo(600), countedAmount: 1 },
          capturedAt,
        },
      ]);

      expect(cash.close).toHaveBeenCalledWith('est-1', 'user-1', expect.anything(), { closedAt: new Date(capturedAt) });
    });

    it('une heure de saisie invraisemblable est ignorée (horodatage serveur)', async () => {
      stockMovements.create.mockResolvedValue({ id: 'op-2' });
      const farFuture = new Date(Date.now() + 3 * 24 * 3600_000).toISOString();

      await service.processBatch('est-1', 'user-1', [
        {
          id: 'op-2',
          entityType: 'stock_movement',
          deviceId: 'd',
          payload: { productId: 'p1', type: 'in', quantity: 5 },
          capturedAt: farFuture,
        },
      ]);

      expect(stockMovements.create).toHaveBeenCalledWith('est-1', 'p1', 'user-1', expect.anything(), { createdAt: undefined });
    });
  });
});

describe('resolveCapturedAt', () => {
  const now = Date.parse('2026-10-03T12:00:00.000Z');

  it('accepte une heure passée récente et une légère avance (fuseaux horaires)', () => {
    expect(resolveCapturedAt('2026-10-03T09:00:00.000Z', now)?.toISOString()).toBe('2026-10-03T09:00:00.000Z');
    expect(resolveCapturedAt('2026-10-04T10:00:00.000Z', now)).toBeDefined();
  });

  it('rejette le futur au-delà de 24h, le passé au-delà de 30 jours, une valeur absente ou illisible', () => {
    expect(resolveCapturedAt('2026-10-04T12:00:01.000Z', now)).toBeUndefined();
    expect(resolveCapturedAt('2026-09-03T11:59:59.000Z', now)).toBeUndefined();
    expect(resolveCapturedAt(undefined, now)).toBeUndefined();
    expect(resolveCapturedAt('pas une date', now)).toBeUndefined();
  });

  it('accepte exactement 30 jours dans le passé', () => {
    expect(resolveCapturedAt('2026-09-03T12:00:00.000Z', now)).toBeDefined();
  });
});
