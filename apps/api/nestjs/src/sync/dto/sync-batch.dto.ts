import { Type } from 'class-transformer';
import { ArrayMinSize, ArrayMaxSize, IsArray, IsDateString, IsIn, IsObject, IsOptional, IsString, IsUUID, ValidateNested } from 'class-validator';

/**
 * entityType names match the domains that support offline capture (prompt
 * maître §25) — sale bundles the payment, matching our data model (also used
 * for the checkout of a table's addition, `payload.orderId`/`tableId` set).
 * 'loss'/'purchase'/'cash_closing' extend coverage to Pertes, Achats et
 * Clôture de caisse (décision actée 2026-09-13, voir docs/api/sync.md).
 */
export type SyncEntityType =
  | 'sale'
  | 'stock_movement'
  | 'expense'
  | 'loss'
  | 'purchase'
  | 'cash_closing'
  | 'order_open'
  | 'order_item_add'
  | 'order_item_set'
  | 'order_item_remove';

/**
 * 'order_*' : ouverture de table et modification d'une addition saisies hors
 * ligne (phase 4, 2026-10-03, voir docs/api/sync.md) — toutes idempotentes,
 * les écritures de quantité refusant explicitement un conflit.
 */
export const SYNC_ENTITY_TYPES: SyncEntityType[] = [
  'sale',
  'stock_movement',
  'expense',
  'loss',
  'purchase',
  'cash_closing',
  'order_open',
  'order_item_add',
  'order_item_set',
  'order_item_remove',
];

export class SyncOperationDto {
  /** Client-generated UUID, reused as both the SyncOperation id and the created entity's id — see docs/api/sync.md. */
  @IsUUID()
  id!: string;

  @IsIn(SYNC_ENTITY_TYPES)
  entityType!: SyncEntityType;

  @IsString()
  deviceId!: string;

  @IsObject()
  payload!: Record<string, unknown>;

  /**
   * Moment où l'opération a été saisie sur l'appareil (hors ligne). Sans lui,
   * une vente/un mouvement/une perte/une clôture saisi hors ligne prenait la
   * date de la synchronisation — voir `SyncService.resolveCapturedAt` pour
   * les bornes de plausibilité appliquées côté serveur.
   */
  @IsOptional()
  @IsDateString()
  capturedAt?: string;
}

export class SyncBatchDto {
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(100)
  @ValidateNested({ each: true })
  @Type(() => SyncOperationDto)
  operations!: SyncOperationDto[];
}
