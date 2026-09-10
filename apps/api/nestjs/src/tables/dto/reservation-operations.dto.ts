import { IsDateString, IsOptional, IsString, MinLength } from 'class-validator';

export class CreateReservationDto {
  @IsOptional()
  @IsString()
  @MinLength(1)
  customerName?: string;

  @IsOptional()
  @IsString()
  phone?: string;

  @IsDateString()
  reservedAt!: string;
}
