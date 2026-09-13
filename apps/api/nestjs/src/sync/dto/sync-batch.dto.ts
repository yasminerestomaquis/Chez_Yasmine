import { Type } from 'class-transformer';
import { ArrayMinSize, ArrayMaxSize, IsArray, IsIn, IsObject, IsString, IsUUID, ValidateNested } from 'class-validator';

/**
 * entityType names match the domains that support offline capture (prompt
 * maître §25) — sale bundles the payment, matching our data model (also used
 * for the checkout of a table's addition, `payload.orderId`/`tableId` set).
 * 'loss'/'purchase'/'cash_closing' extend coverage to Pertes, Achats et
 * Clôture de caisse (décision actée 2026-09-13, voir docs/api/sync.md).
 */
export type SyncEntityType = 'sale' | 'stock_movement' | 'expense' | 'loss' | 'purchase' | 'cash_closing';

export class SyncOperationDto {
  /** Client-generated UUID, reused as both the SyncOperation id and the created entity's id — see docs/api/sync.md. */
  @IsUUID()
  id!: string;

  @IsIn(['sale', 'stock_movement', 'expense', 'loss', 'purchase', 'cash_closing'])
  entityType!: SyncEntityType;

  @IsString()
  deviceId!: string;

  @IsObject()
  payload!: Record<string, unknown>;
}

export class SyncBatchDto {
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(100)
  @ValidateNested({ each: true })
  @Type(() => SyncOperationDto)
  operations!: SyncOperationDto[];
}
