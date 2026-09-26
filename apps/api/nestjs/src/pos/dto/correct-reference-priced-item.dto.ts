import { IsNumber, Min } from 'class-validator';

export class CorrectReferencePricedItemDto {
  @IsNumber()
  @Min(0.01)
  amountPaid!: number;
}
