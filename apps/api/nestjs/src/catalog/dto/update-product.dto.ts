import { IsBoolean, IsIn, IsInt, IsNumber, IsOptional, IsString, IsUUID, Min, MinLength } from 'class-validator';

/** Excludes stockQuantity on purpose — stock changes go through movements (Phase 6), never a direct product edit. */
export class UpdateProductDto {
  @IsOptional()
  @IsString()
  @MinLength(1)
  name?: string;

  @IsOptional()
  @IsUUID()
  categoryId?: string;

  @IsOptional()
  @IsUUID()
  supplierId?: string;

  @IsOptional()
  @IsString()
  reference?: string;

  @IsOptional()
  @IsString()
  description?: string;

  @IsOptional()
  @IsString()
  barcode?: string;

  @IsOptional()
  @IsString()
  qrCode?: string;

  @IsOptional()
  @IsString()
  unit?: string;

  @IsOptional()
  @IsNumber()
  @Min(0)
  purchasePrice?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  salePrice?: number;

  /** Prix de vente saisi à chaque vente plutôt que fixé au catalogue, pour un produit de catégorie fixe (ex. Gbêlê) — voir schema.prisma. */
  @IsOptional()
  @IsBoolean()
  requiresPriceAtSale?: boolean;

  /** Valeur indicative du stock initial, uniquement quand requiresPriceAtSale est vrai — jamais utilisée par la caisse. */
  @IsOptional()
  @IsNumber()
  @Min(0)
  referenceSalePrice?: number;

  /** Prix de vente alternatif pour une seule unité, quand salePrice représente un lot (catégories à prix par casier uniquement). */
  @IsOptional()
  @IsNumber()
  @Min(0)
  unitSalePrice?: number;

  @IsOptional()
  @IsInt()
  @Min(1)
  bottlesPerCase?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  purchasePricePerCase?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  vatRate?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  minStock?: number;

  @IsOptional()
  @IsIn(['active', 'archived'])
  status?: 'active' | 'archived';
}
