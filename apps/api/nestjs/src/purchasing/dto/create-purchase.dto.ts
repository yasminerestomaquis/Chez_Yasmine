import { Type } from 'class-transformer';
import { ArrayMinSize, IsArray, IsDateString, IsInt, IsOptional, IsUUID, Min, ValidateNested } from 'class-validator';

export class PurchaseItemDto {
  @IsUUID()
  productId!: string;

  /** Nbre de casiers commandés — bottlesPerCase/purchasePricePerCase sont dérivés côté serveur depuis le Catalogue, jamais acceptés du client. */
  @IsInt()
  @Min(1)
  casesOrdered!: number;
}

export class CreatePurchaseDto {
  /** Client-generated UUID — same idempotent-replay pattern as sales/pertes (voir docs/api/sync.md). */
  @IsOptional()
  @IsUUID()
  id?: string;

  @IsOptional()
  @IsUUID()
  supplierId?: string;

  /** N° de la commande — suggéré côté client (compteur par fournisseur), librement éditable. */
  @IsInt()
  @Min(1)
  orderNumber!: number;

  /** Par défaut aujourd'hui si omis. */
  @IsOptional()
  @IsDateString()
  orderDate?: string;

  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => PurchaseItemDto)
  items!: PurchaseItemDto[];
}
