import { Injectable, Logger } from '@nestjs/common';
import { AuthorizationService } from '../auth/authorization.service.js';
import { PrismaService } from '../prisma/prisma.service.js';
import { SalesService } from '../pos/sales.service.js';
import { StockMovementsService } from '../stock/stock-movements.service.js';
import type { SyncEntityType, SyncOperationDto } from './dto/sync-batch.dto.js';

/** Permission required to accept an operation of a given entity type — checked per-operation, not once for the whole batch, since a single sync request can legitimately mix a sale and a stock correction. */
const REQUIRED_PERMISSION: Record<SyncEntityType, string> = {
  sale: 'pos.sell',
  stock_movement: 'stock.manage',
};

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
    switch (operation.entityType) {
      case 'sale':
        return this.sales.create(establishmentId, userId, { ...(operation.payload as object), id: operation.id } as any);
      case 'stock_movement': {
        const { productId, ...rest } = operation.payload as { productId: string };
        return this.stockMovements.create(establishmentId, productId, userId, { ...rest, id: operation.id } as any);
      }
    }
  }
}
