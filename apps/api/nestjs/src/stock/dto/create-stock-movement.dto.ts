import { IsIn, IsNumber, IsOptional, IsString, Min } from 'class-validator';
import type { ManualStockMovementType } from '../stock-math.js';

export class CreateStockMovementDto {
  @IsIn(['in', 'out', 'adjustment', 'loss'])
  type!: ManualStockMovementType;

  @IsNumber()
  @Min(0)
  quantity!: number;

  @IsOptional()
  @IsString()
  reason?: string;
}
