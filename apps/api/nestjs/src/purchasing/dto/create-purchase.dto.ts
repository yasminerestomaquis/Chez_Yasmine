import { Type } from 'class-transformer';
import { ArrayMinSize, IsArray, IsDateString, IsInt, IsNumber, IsOptional, IsUUID, Min, ValidateNested } from 'class-validator';

export class PurchaseItemDto {
  @IsUUID()
  productId!: string;

  /**
   * Produit à prix par casier (Bières, Vins, Sucreries) : nbre de casiers
   * commandés — bottlesPerCase/purchasePricePerCase sont dérivés côté
   * serveur depuis le Catalogue, jamais acceptés du client.
   */
  @IsOptional()
  @IsInt()
  @Min(1)
  casesOrdered?: number;

  /**
   * Produit à prix variable (Poulets, Poissons, Plats africains) : quantité
   * achetée et prix d'achat unitaire, connus directement (pas de casier) —
   * PurchasesService.resolveLines exige l'un ou l'autre selon la catégorie
   * réelle du produit, jamais les deux.
   */
  @IsOptional()
  @IsInt()
  @Min(1)
  quantityOrdered?: number;

  @IsOptional()
  @IsNumber()
  @Min(0.01)
  unitPurchasePrice?: number;
}

export class CreatePurchaseDto {
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
