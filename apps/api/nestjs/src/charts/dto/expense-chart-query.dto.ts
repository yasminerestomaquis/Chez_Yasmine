import { IsOptional, IsString, Matches } from 'class-validator';

export class ExpenseWeeklyQueryDto {
  /** Any date within the target week; the service snaps it back to that week's Monday — same convention as chart-query.dto.ts. */
  @IsOptional()
  @IsString()
  weekStart?: string;
}

export class ExpenseWeeklyByCategoryQueryDto extends ExpenseWeeklyQueryDto {
  @IsOptional()
  @IsString()
  category?: string;
}

export class ExpenseMonthlyQueryDto {
  @IsOptional()
  @Matches(/^\d{4}$/, { message: 'year doit être une année à 4 chiffres' })
  year?: string;
}

export class ExpenseTopQueryDto {
  @IsOptional()
  @IsString()
  from?: string;

  @IsOptional()
  @IsString()
  to?: string;
}
