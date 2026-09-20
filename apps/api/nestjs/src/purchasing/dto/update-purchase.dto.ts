import { Type } from 'class-transformer';
import { ArrayMinSize, IsArray, IsBoolean, IsDateString, IsInt, IsOptional, IsUUID, Min, ValidateNested } from 'class-validator';
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

  /** Valide une commande en attente (bouton « Créer la commande ») : le stock entre alors. Ignoré pour une commande déjà validée. */
  @IsOptional()
  @IsBoolean()
  confirm?: boolean;

  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => PurchaseItemDto)
  items!: PurchaseItemDto[];
}
