import { IsNumber, IsOptional, IsString, IsUUID, Min } from 'class-validator';

export class CreateLossDto {
  /** Client-generated UUID — same idempotent-replay pattern as sales/stock movements (Phase 9). */
  @IsOptional()
  @IsUUID()
  id?: string;

  @IsUUID()
  productId!: string;

  @IsNumber()
  @Min(0.01)
  quantity!: number;

  @IsOptional()
  @IsString()
  reason?: string;
}
