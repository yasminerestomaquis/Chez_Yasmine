import { IsIn, IsNumber, IsOptional, IsString, IsUUID, Min } from 'class-validator';
import type { ManualStockMovementType } from '../stock-math.js';

export class CreateStockMovementDto {
  /** Client-generated UUID — lets an offline movement be replayed safely (see Phase 9 / docs/api/sync.md). */
  @IsOptional()
  @IsUUID()
  id?: string;

  /** 'loss' is deliberately not accepted here since Phase 12 — see src/losses/ — so that every stock loss carries a Loss accounting record, not just a StockMovement. */
  @IsIn(['in', 'out', 'adjustment'])
  type!: ManualStockMovementType;

  @IsNumber()
  @Min(0)
  quantity!: number;

  @IsOptional()
  @IsString()
  reason?: string;
}
