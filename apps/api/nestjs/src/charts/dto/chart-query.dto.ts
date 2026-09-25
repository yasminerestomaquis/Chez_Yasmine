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
  /** @deprecated Remplacé par `productIds` (sélection multiple, 2026-09-22) — encore accepté pour compatibilité. */
  @IsOptional()
  @IsString()
  productId?: string;

  /** CSV d'identifiants de produit — sélection multiple, agrégée en une seule série (somme), même principe que `WeeklyByCategoryQueryDto.categoryIds`. */
  @IsOptional()
  @IsString()
  productIds?: string;
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
  /** CSV d'un ou plusieurs identifiants de produit — sélection multiple, doit être de la même catégorie (validé côté service). */
  @IsString()
  productIds!: string;
}

export class ActiveStockListingQueryDto {
  /**
   * CSV d'identifiants de catégorie — filtre optionnel du listing "Stock
   * actif" (module Stock, décision utilisateur du 2026-09-25). Absent/vide :
   * toutes les catégories éligibles (les catégories à prix variable — Plats
   * africains/Poissons/Poulets — sont de toute façon toujours exclues côté
   * service, ce filtre ne peut que restreindre davantage, jamais les inclure).
   */
  @IsOptional()
  @IsString()
  categoryIds?: string;
}
