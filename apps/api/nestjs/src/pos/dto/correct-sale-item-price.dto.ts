import { IsNumber, Min } from 'class-validator';

export class CorrectSaleItemPriceDto {
  @IsNumber()
  @Min(0.01)
  unitPrice!: number;
}
