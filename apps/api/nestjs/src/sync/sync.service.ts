import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { AuthorizationService } from '../auth/authorization.service.js';
import { PrismaService } from '../prisma/prisma.service.js';
import { CashService } from '../cash/cash.service.js';
import { ExpensesService } from '../expenses/expenses.service.js';
import { LossesService } from '../losses/losses.service.js';
import { SalesService } from '../pos/sales.service.js';
import { PurchasesService } from '../purchasing/purchases.service.js';
import { StockMovementsService } from '../stock/stock-movements.service.js';
import { OrdersService } from '../tables/orders.service.js';
import type { SyncEntityType, SyncOperationDto } from './dto/sync-batch.dto.js';

/** Permission required to accept an operation of a given entity type — checked per-operation, not once for the whole batch, since a single sync request can legitimately mix a sale and a stock correction. */
const REQUIRED_PERMISSION: Record<SyncEntityType, string> = {
  sale: 'pos.sell',
  stock_movement: 'stock.manage',
  expense: 'expenses.manage',
  loss: 'losses.manage',
  purchase: 'purchases.manage',
  cash_closing: 'cash.manage',
  // Les routes d'additions (OrdersController) exigent `tables.manage`.
  order_open: 'tables.manage',
  order_item_add: 'tables.manage',
  order_item_set: 'tables.manage',
  order_item_remove: 'tables.manage',
};

/**
 * Bornes de plausibilité de `SyncOperationDto.capturedAt` (heure de l'appareil,
 * donc non fiable) : au plus 24h dans le futur (fuseaux horaires, même
 * tolérance que `SalesService`/`LossesService`) et au plus 30 jours dans le
 * passé. Hors bornes, l'heure est ignorée et l'horodatage serveur s'applique
 * — une horloge d'appareil déréglée ne doit pas réécrire l'historique.
 */
const MAX_CAPTURED_FUTURE_MS = 24 * 60 * 60 * 1000;
const MAX_CAPTURED_AGE_MS = 30 * 24 * 60 * 60 * 1000;

export function resolveCapturedAt(raw: string | undefined, now: number = Date.now()): Date | undefined {
  if (!raw) return undefined;
  const date = new Date(raw);
  const time = date.getTime();
  if (Number.isNaN(time)) return undefined;
  if (time > now + MAX_CAPTURED_FUTURE_MS || time < now - MAX_CAPTURED_AGE_MS) return undefined;
  return date;
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function requireUuid(payload: Record<string, unknown>, key: string): string {
  const value = payload[key];
  if (typeof value !== 'string' || !UUID_PATTERN.test(value)) {
    throw new BadRequestException(`Champ « ${key} » invalide dans l'opération`);
  }
  return value;
}

function requireNumber(payload: Record<string, unknown>, key: string): number {
  const value = payload[key];
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new BadRequestException(`Champ « ${key} » invalide dans l'opération`);
  }
  return value;
}

function optionalNumber(payload: Record<string, unknown>, key: string): number | undefined {
  return payload[key] === undefined || payload[key] === null ? undefined : requireNumber(payload, key);
}

export interface SyncOperationResult {
  id: string;
  status: 'SYNCED' | 'FAILED' | 'CONFLICT';
  result?: unknown;
  error?: string;
}

@Injectable()
export class SyncService {
  private readonly logger = new Logger(SyncService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly authorization: AuthorizationService,
    private readonly sales: SalesService,
    private readonly stockMovements: StockMovementsService,
    private readonly expenses: ExpensesService,
    private readonly losses: LossesService,
    private readonly purchases: PurchasesService,
    private readonly cash: CashService,
    private readonly orders: OrdersService,
  ) {}

  async processBatch(establishmentId: string, userId: string, operations: SyncOperationDto[]): Promise<SyncOperationResult[]> {
    const results: SyncOperationResult[] = [];
    for (const operation of operations) {
      results.push(await this.processOne(establishmentId, userId, operation));
    }
    return results;
  }

  private async processOne(establishmentId: string, userId: string, operation: SyncOperationDto): Promise<SyncOperationResult> {
    const existing = await this.prisma.syncOperation.findUnique({ where: { id: operation.id } });
    if (existing?.status === 'SYNCED') {
      return { id: operation.id, status: 'SYNCED', result: existing.payload };
    }

    const allowed = await this.authorization.hasAllPermissions(userId, establishmentId, [
      REQUIRED_PERMISSION[operation.entityType],
    ]);
    if (!allowed) {
      return this.recordFailure(establishmentId, userId, operation, 'FAILED', "Permission refusée pour cette opération");
    }

    await this.prisma.syncOperation.upsert({
      where: { id: operation.id },
      create: {
        id: operation.id,
        operationType: 'create',
        entityType: operation.entityType,
        entityId: operation.id,
        payload: operation.payload as any,
        userId,
        deviceId: operation.deviceId,
        status: 'SYNCING',
        attemptCount: 1,
      },
      update: { status: 'SYNCING', attemptCount: { increment: 1 } },
    });

    try {
      const result = await this.dispatch(establishmentId, userId, operation);
      await this.prisma.syncOperation.update({ where: { id: operation.id }, data: { status: 'SYNCED' } });
      return { id: operation.id, status: 'SYNCED', result };
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Erreur de synchronisation';
      this.logger.warn(`Sync operation ${operation.id} (${operation.entityType}) failed: ${message}`);
      return this.recordFailure(establishmentId, userId, operation, 'CONFLICT', message);
    }
  }

  private async recordFailure(
    establishmentId: string,
    userId: string,
    operation: SyncOperationDto,
    status: 'FAILED' | 'CONFLICT',
    message: string,
  ): Promise<SyncOperationResult> {
    await this.prisma.syncOperation.upsert({
      where: { id: operation.id },
      create: {
        id: operation.id,
        operationType: 'create',
        entityType: operation.entityType,
        entityId: operation.id,
        payload: { ...operation.payload, _lastError: message } as any,
        userId,
        deviceId: operation.deviceId,
        status,
        attemptCount: 1,
      },
      update: { status, attemptCount: { increment: 1 }, payload: { ...operation.payload, _lastError: message } as any },
    });
    return { id: operation.id, status, error: message };
  }

  private dispatch(establishmentId: string, userId: string, operation: SyncOperationDto): Promise<unknown> {
    const capturedAt = resolveCapturedAt(operation.capturedAt);
    switch (operation.entityType) {
      case 'sale':
        return this.dispatchSale(establishmentId, userId, operation, capturedAt);
      case 'stock_movement': {
        const { productId, ...rest } = operation.payload as { productId: string };
        return this.stockMovements.create(
          establishmentId,
          productId,
          userId,
          { ...rest, id: operation.id } as any,
          { createdAt: capturedAt },
        );
      }
      case 'expense':
        return this.expenses.create(establishmentId, userId, { ...(operation.payload as object), id: operation.id } as any);
      case 'loss':
        return this.dispatchLoss(establishmentId, userId, operation, capturedAt);
      case 'purchase':
        return this.purchases.create(establishmentId, userId, { ...(operation.payload as object), id: operation.id } as any);
      case 'order_open': {
        const payload = operation.payload;
        const guestCount = payload.guestCount;
        return this.orders.openOfflineOrder(
          establishmentId,
          userId,
          {
            id: operation.id,
            tableId: requireUuid(payload, 'tableId'),
            guestCount: typeof guestCount === 'number' ? guestCount : undefined,
          },
          capturedAt,
        );
      }
      case 'order_item_add': {
        const payload = operation.payload;
        return this.orders.addItemWithId(
          establishmentId,
          requireUuid(payload, 'orderId'),
          requireUuid(payload, 'itemId'),
          {
            productId: requireUuid(payload, 'productId'),
            quantity: optionalNumber(payload, 'quantity'),
            unitPrice: optionalNumber(payload, 'unitPrice'),
            amountPaid: optionalNumber(payload, 'amountPaid'),
            sellAsUnit: payload.sellAsUnit === true,
          },
        );
      }
      case 'order_item_set': {
        const payload = operation.payload;
        return this.orders.setItemQuantityIfExpected(
          establishmentId,
          requireUuid(payload, 'orderId'),
          requireUuid(payload, 'itemId'),
          requireNumber(payload, 'expectedQuantity'),
          requireNumber(payload, 'quantity'),
        );
      }
      case 'order_item_remove': {
        const payload = operation.payload;
        return this.orders.removeItemIfExpected(
          establishmentId,
          requireUuid(payload, 'orderId'),
          requireUuid(payload, 'itemId'),
          requireNumber(payload, 'expectedQuantity'),
        );
      }
      case 'cash_closing':
        return this.cash.close(
          establishmentId,
          userId,
          { ...(operation.payload as object), id: operation.id } as any,
          { closedAt: capturedAt },
        );
    }
  }

  /**
   * La date de vente CHOISIE par le caissier (champ Date du dialogue Paiement)
   * n'est conservée que si l'auteur porte `pos.set_date`, comme sur la route
   * HTTP (`SalesController.create`) ; sinon elle est ignorée. À défaut de date
   * choisie, la vente reçoit l'heure réelle de saisie sur l'appareil.
   */
  private async dispatchSale(
    establishmentId: string,
    userId: string,
    operation: SyncOperationDto,
    capturedAt: Date | undefined,
  ): Promise<unknown> {
    const { createdAt: chosen, ...rest } = operation.payload as { createdAt?: string };
    const maySetDate = chosen
      ? await this.authorization.hasAllPermissions(userId, establishmentId, ['pos.set_date'])
      : false;
    const createdAt = maySetDate ? chosen : capturedAt?.toISOString();
    return this.sales.create(establishmentId, userId, {
      ...rest,
      ...(createdAt ? { createdAt } : {}),
      id: operation.id,
    } as any);
  }

  /** La date saisie d'une perte (antidatage) n'est conservée que si l'auteur porte `losses.edit`, comme sur la route HTTP ; sinon elle est ignorée (horodatage serveur). */
  private async dispatchLoss(
    establishmentId: string,
    userId: string,
    operation: SyncOperationDto,
    capturedAt: Date | undefined,
  ): Promise<unknown> {
    const { createdAt: chosen, ...rest } = operation.payload as { createdAt?: string };
    const mayBackdate = chosen
      ? await this.authorization.hasAllPermissions(userId, establishmentId, ['losses.edit'])
      : false;
    const createdAt = mayBackdate ? chosen : capturedAt?.toISOString();
    return this.losses.create(establishmentId, userId, {
      ...rest,
      ...(createdAt ? { createdAt } : {}),
      id: operation.id,
    } as any);
  }
}
