import { IsIn, IsNumber, IsOptional, IsString, IsUUID, Min } from 'class-validator';
import type { ManualStockMovementType } from '../stock-math.js';

export class CreateStockMovementDto {
  /** Client-generated UUID — lets an offline movement be replayed safely (see Phase 9 / docs/api/sync.md). */
  @IsOptional()
  @IsUUID()
  id?: string;

  @IsIn(['in', 'out', 'adjustment', 'loss'])
  type!: ManualStockMovementType;

  @IsNumber()
  @Min(0)
  quantity!: number;

  @IsOptional()
  @IsString()
  reason?: string;
}
