import { IsArray, IsDateString, IsNumber, IsOptional, ValidateNested } from 'class-validator';
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

/** Modification de la période d'une paie existante (au moins un des deux champs). */
export class UpdatePayrollRunDto {
  @IsOptional()
  @IsDateString()
  periodStart?: string;

  @IsOptional()
  @IsDateString()
  periodEnd?: string;
}

export class UpdatePayrollLineDto {
  @IsNumber()
  advance!: number;

  @IsNumber()
  adjustment!: number;
}
