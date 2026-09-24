import { Type } from 'class-transformer';
import { ArrayMinSize, IsArray, IsDateString, IsIn, IsInt, IsNumber, IsOptional, IsUUID, Min, ValidateNested } from 'class-validator';

export class PurchaseItemDto {
  @IsUUID()
  productId!: string;

  /**
   * Nbre de casiers commandés — bottlesPerCase/purchasePricePerCase sont
   * dérivés côté serveur depuis le Catalogue, jamais acceptés du client.
   * Requis pour un produit à prix par casier (Bières, Vins, Sucreries),
   * absent pour un produit à prix de référence variable commandé au litre
   * (ex. Gbêlê — voir `litersOrdered`).
   */
  @IsOptional()
  @IsInt()
  @Min(1)
  casesOrdered?: number;

  /**
   * Litres commandés — uniquement pour un produit à prix de référence
   * variable (`Product.referenceSalePrice`, ex. Gbêlê — décision utilisateur
   * du 2026-09-24) : saisie libre (plus figée à 25/50 L depuis le
   * 2026-09-25). Le prix d'achat par litre (`Product.purchasePrice`,
   * éditable au Catalogue) est dérivé côté serveur, jamais accepté du client
   * — voir `PurchasesService.resolveLines`.
   */
  @IsOptional()
  @IsNumber()
  @Min(0.01)
  litersOrdered?: number;
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

  /**
   * 'pending' : commande en attente (projection, 2026-09-20) — enregistrée
   * sans entrée de stock ; 'received' (défaut) : commande validée, le stock
   * entre. Une commande en attente se confirme via `UpdatePurchaseDto.confirm`.
   */
  @IsOptional()
  @IsIn(['pending', 'received'])
  status?: 'pending' | 'received';

  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => PurchaseItemDto)
  items!: PurchaseItemDto[];
}
