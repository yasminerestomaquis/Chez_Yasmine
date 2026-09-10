import { ArrayMinSize, IsArray, IsInt, IsNumber, IsOptional, IsUUID, Min } from 'class-validator';

export class OpenTableDto {
  @IsOptional()
  @IsInt()
  @Min(1)
  guestCount?: number;
}

export class AddOrderItemDto {
  @IsUUID()
  productId!: string;

  @IsNumber()
  @Min(0.01)
  quantity!: number;

  /** Requis si le produit appartient à une catégorie à prix variable (Poulets, Poissons, Plats africains) — voir OrdersService.addItem. Ignoré pour un produit à prix fixe (le prix catalogue prévaut toujours). */
  @IsOptional()
  @IsNumber()
  @Min(0.01)
  unitPrice?: number;
}

export class UpdateOrderItemDto {
  @IsNumber()
  @Min(0.01)
  quantity!: number;
}

export class TransferOrderDto {
  @IsUUID()
  toTableId!: string;
}

export class MergeOrderDto {
  @IsUUID()
  intoOrderId!: string;
}

export class SplitOrderDto {
  @IsArray()
  @ArrayMinSize(1)
  @IsUUID('4', { each: true })
  itemIds!: string[];

  @IsUUID()
  toTableId!: string;
}
