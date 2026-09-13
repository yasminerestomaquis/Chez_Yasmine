import { IsDateString, IsNumber, IsOptional, IsUUID, Min } from 'class-validator';

export class CreateCashClosingDto {
  /** Client-generated UUID — same idempotent-replay pattern as sales/pertes (voir docs/api/sync.md). */
  @IsOptional()
  @IsUUID()
  id?: string;

  /** When the counted period started (e.g. start of the shift/day) — the server computes expected cash from sales/expenses since then. */
  @IsDateString()
  openedAt!: string;

  @IsNumber()
  @Min(0)
  countedAmount!: number;
}
