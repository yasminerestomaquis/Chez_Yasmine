import { IsIn, IsOptional, IsString, Matches } from 'class-validator';

export type ChartMetric = 'revenue' | 'profit';

export class WeeklyChartQueryDto {
  @IsIn(['revenue', 'profit'])
  metric!: ChartMetric;

  /** Any date within the target week; the service snaps it back to that week's Monday. */
  @IsOptional()
  @IsString()
  weekStart?: string;
}

export class WeeklyByCategoryQueryDto extends WeeklyChartQueryDto {
  /** CSV d'identifiants de catégorie — sélection multiple, agrégée en une seule série (somme). */
  @IsOptional()
  @IsString()
  categoryIds?: string;
}

export class WeeklyByProductQueryDto extends WeeklyChartQueryDto {
  @IsOptional()
  @IsString()
  productId?: string;
}

export class MonthlyChartQueryDto {
  @IsIn(['revenue', 'profit'])
  metric!: ChartMetric;

  @IsOptional()
  @Matches(/^\d{4}$/, { message: 'year doit être une année à 4 chiffres' })
  year?: string;
}

export class TopChartQueryDto {
  @IsIn(['revenue', 'profit'])
  metric!: ChartMetric;

  @IsOptional()
  @IsString()
  from?: string;

  @IsOptional()
  @IsString()
  to?: string;
}

export class StockLotsQueryDto {
  @IsString()
  productId!: string;
}
