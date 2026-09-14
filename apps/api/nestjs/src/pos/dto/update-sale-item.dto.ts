import { IsNumber, Min } from 'class-validator';

export class UpdateSaleItemDto {
  @IsNumber()
  @Min(0.01)
  quantity!: number;
}
