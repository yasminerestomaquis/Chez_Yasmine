import { IsDateString, IsIn, IsInt, IsNumber, IsOptional, IsString, IsUUID, Min, MinLength } from 'class-validator';
import { Type } from 'class-transformer';

export type ExpensePeriodicity = 'one_off' | 'recurring';

export class CreateExpenseDto {
  /** Client-generated UUID — permet de rejouer sans risque une dépense saisie hors ligne (file de sync). */
  @IsOptional()
  @IsUUID()
  id?: string;

  @IsString()
  @MinLength(1)
  label!: string;

  @IsOptional()
  @IsString()
  category?: string;

  @IsNumber()
  @Min(0.01)
  amount!: number;

  @IsOptional()
  @IsDateString()
  expenseDate?: string;

  /** Étiquette informative — voir docs/api/expenses.md. Ne change rien au calcul du bénéfice net. */
  @IsOptional()
  @IsIn(['one_off', 'recurring'])
  periodicity?: ExpensePeriodicity;

  @IsOptional()
  @IsString()
  note?: string;

  /** Numéro de marché — pertinent uniquement pour category === 'Marché', jamais imposé (même principe que Purchase.orderNumber). */
  @IsOptional()
  @IsInt()
  @Min(1)
  marketNumber?: number;

  @IsOptional()
  @IsIn(['cash', 'mobile_money', 'bank_transfer'])
  paymentMethod?: string;

  @IsOptional()
  @IsIn(['paid', 'pending', 'cancelled'])
  status?: string;
}

export class UpdateExpenseDto {
  @IsOptional()
  @IsString()
  @MinLength(1)
  label?: string;

  @IsOptional()
  @IsString()
  category?: string;

  @IsOptional()
  @IsNumber()
  @Min(0.01)
  amount?: number;

  @IsOptional()
  @IsDateString()
  expenseDate?: string;

  @IsOptional()
  @IsIn(['one_off', 'recurring'])
  periodicity?: ExpensePeriodicity;

  @IsOptional()
  @IsString()
  note?: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  marketNumber?: number;

  @IsOptional()
  @IsIn(['cash', 'mobile_money', 'bank_transfer'])
  paymentMethod?: string;

  @IsOptional()
  @IsIn(['paid', 'pending', 'cancelled'])
  status?: string;
}

export class ExpenseHistoryQueryDto {
  @IsOptional()
  @IsIn(['year', 'month', 'week'])
  period?: 'year' | 'month' | 'week';

  @IsOptional()
  @Type(() => Number)
  year?: number;

  @IsOptional()
  @Type(() => Number)
  month?: number;

  @IsOptional()
  weekOf?: string;

  @IsOptional()
  @IsString()
  category?: string;

  @IsOptional()
  @IsIn(['paid', 'pending', 'cancelled'])
  status?: string;

  @IsOptional()
  @IsIn(['cash', 'mobile_money', 'bank_transfer'])
  paymentMethod?: string;

  @IsOptional()
  @Type(() => Number)
  page?: number;

  @IsOptional()
  @Type(() => Number)
  pageSize?: number;
}
