import { Type } from 'class-transformer';
import { ArrayMinSize, IsArray, IsIn, IsInt, IsNumber, IsOptional, IsString, IsUUID, Min, ValidateNested } from 'class-validator';

export class SaleItemDto {
  @IsUUID()
  productId!: string;

  @IsNumber()
  @Min(0.01)
  quantity!: number;

  /**
   * Prix de vente saisi par le caissier — utilisé uniquement pour un produit
   * de catégorie à prix variable (ex. Poulets/Poissons/Plats africains, voir
   * docs/api/catalog.md) : SalesService l'exige dans ce cas et ignore ce
   * champ (utilise toujours product.salePrice) pour tout autre produit —
   * le client n'est jamais source de vérité sur le prix d'un produit à prix
   * fixe.
   */
  @IsOptional()
  @IsNumber()
  @Min(0)
  unitPrice?: number;
}

export class SalePaymentDto {
  @IsIn(['cash', 'mobile_money', 'card', 'credit'])
  method!: 'cash' | 'mobile_money' | 'card' | 'credit';

  @IsNumber()
  @Min(0.01)
  amount!: number;
}

export class SaleDiscountDto {
  @IsIn(['amount', 'percent'])
  type!: 'amount' | 'percent';

  @IsNumber()
  @Min(0)
  value!: number;
}

export class CreateSaleDto {
  /** Client-generated UUID — lets an offline sale be replayed safely (see Phase 9 / docs/api/sync.md) without double-charging stock. */
  @IsOptional()
  @IsUUID()
  id?: string;

  @IsOptional()
  @IsIn(['pos', 'table'])
  source?: 'pos' | 'table';

  @IsOptional()
  @IsUUID()
  tableId?: string;

  @IsOptional()
  @IsUUID()
  orderId?: string;

  @IsOptional()
  @IsUUID()
  customerId?: string;

  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => SaleItemDto)
  items!: SaleItemDto[];

  @IsOptional()
  @ValidateNested()
  @Type(() => SaleDiscountDto)
  discount?: SaleDiscountDto;

  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => SalePaymentDto)
  payments!: SalePaymentDto[];

  @IsOptional()
  @IsString()
  reason?: string;

  /** N° de la commande d'achat (Bières/Vins/Sucreries) dont provient cette vente — saisi en caisse, jamais imposé ni vérifié contre Purchase.orderNumber. */
  @IsOptional()
  @IsInt()
  @Min(1)
  orderNumber?: number;

  /** N° de marché (Poulets/Poissons/Plats africains) dont provient cette vente — même principe, voir Expense.marketNumber. */
  @IsOptional()
  @IsInt()
  @Min(1)
  marketNumber?: number;
}
