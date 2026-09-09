import { IsBoolean, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

export class CreateCategoryDto {
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  name!: string;

  /** Vrai pour une catégorie sans prix fixe (ex. Poulets, Poissons, Plats africains) — voir CategoriesService. */
  @IsOptional()
  @IsBoolean()
  hasVariablePricing?: boolean;

  /** Vrai pour une catégorie vendue par casier (ex. Bières, Vins, Sucreries) — voir CategoriesService. */
  @IsOptional()
  @IsBoolean()
  hasCasePricing?: boolean;
}
