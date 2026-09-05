import { IsDateString, IsNumber, Min } from 'class-validator';

export class CreateCashClosingDto {
  /** When the counted period started (e.g. start of the shift/day) — the server computes expected cash from sales/expenses since then. */
  @IsDateString()
  openedAt!: string;

  @IsNumber()
  @Min(0)
  countedAmount!: number;
}
