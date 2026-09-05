import { Type } from 'class-transformer';
import { ArrayMinSize, ArrayMaxSize, IsArray, IsIn, IsObject, IsString, IsUUID, ValidateNested } from 'class-validator';

/** entityType names match the domains that support offline capture (prompt maître §25) — sale bundles the payment, matching our data model. */
export type SyncEntityType = 'sale' | 'stock_movement';

export class SyncOperationDto {
  /** Client-generated UUID, reused as both the SyncOperation id and the created entity's id — see docs/api/sync.md. */
  @IsUUID()
  id!: string;

  @IsIn(['sale', 'stock_movement'])
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
