import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { AuthorizationService } from '../auth/authorization.service.js';
import type { PrismaService } from '../prisma/prisma.service.js';
import type { ExpensesService } from '../expenses/expenses.service.js';
import type { SalesService } from '../pos/sales.service.js';
import type { StockMovementsService } from '../stock/stock-movements.service.js';
import { SyncService } from './sync.service.js';

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
  let service: SyncService;

  beforeEach(() => {
    prisma = makePrismaMock();
    authorization = { hasAllPermissions: vi.fn().mockResolvedValue(true) };
    sales = { create: vi.fn() };
    stockMovements = { create: vi.fn() };
    expenses = { create: vi.fn() };
    service = new SyncService(
      prisma as unknown as PrismaService,
      authorization as unknown as AuthorizationService,
      sales as unknown as SalesService,
      stockMovements as unknown as StockMovementsService,
      expenses as unknown as ExpensesService,
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

    expect(expenses.create).toHaveBeenCalledWith('est-1', expect.objectContaining({ id: 'op-6', label: 'Eau', amount: 5000 }));
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
});
