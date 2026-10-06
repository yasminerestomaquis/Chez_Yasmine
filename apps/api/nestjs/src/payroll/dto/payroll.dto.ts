import { IsArray, IsDateString, IsNotEmpty, IsNumber, IsOptional, IsString, ValidateNested } from 'class-validator';
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

/** Ajout d'un employé sur une paie existante (ligne créée au salaire hebdomadaire courant). */
export class AddPayrollLineDto {
  @IsString()
  @IsNotEmpty()
  employeeId!: string;
}

export class UpdatePayrollLineDto {
  @IsNumber()
  advance!: number;

  @IsNumber()
  adjustment!: number;
}
