import { IsArray, IsDateString, IsNumber, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';

export class PrepareLineDto {
  employeeId!: string;

  @IsNumber()
  advance!: number;

  @IsNumber()
  adjustment!: number;
}

export class PreparePayrollRunDto {
  @IsDateString()
  periodStart!: string;

  @IsDateString()
  periodEnd!: string;
}

export class UpdatePayrollLineDto {
  @IsNumber()
  advance!: number;

  @IsNumber()
  adjustment!: number;
}
