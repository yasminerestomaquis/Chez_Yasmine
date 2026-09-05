import { ArrayMinSize, IsArray, IsNumber, IsUUID, Min } from 'class-validator';

export class AddOrderItemDto {
  @IsUUID()
  productId!: string;

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
