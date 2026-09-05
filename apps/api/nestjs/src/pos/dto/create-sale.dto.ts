import { Type } from 'class-transformer';
import { ArrayMinSize, IsArray, IsIn, IsNumber, IsOptional, IsString, IsUUID, Min, ValidateNested } from 'class-validator';

export class SaleItemDto {
  @IsUUID()
  productId!: string;

  @IsNumber()
  @Min(0.01)
  quantity!: number;
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
}
