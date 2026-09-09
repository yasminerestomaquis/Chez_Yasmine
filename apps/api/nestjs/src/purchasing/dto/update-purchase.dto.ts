import { Type } from 'class-transformer';
import { ArrayMinSize, IsArray, IsDateString, IsInt, IsOptional, IsUUID, Min, ValidateNested } from 'class-validator';
import { PurchaseItemDto } from './create-purchase.dto.js';

/** Remplace l'intégralité des lignes de la commande (pas d'édition partielle ligne par ligne) — voir PurchasesService.update. */
export class UpdatePurchaseDto {
  @IsOptional()
  @IsUUID()
  supplierId?: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  orderNumber?: number;

  @IsOptional()
  @IsDateString()
  orderDate?: string;

  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => PurchaseItemDto)
  items!: PurchaseItemDto[];
}
