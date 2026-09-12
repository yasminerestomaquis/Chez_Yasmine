import { Transform } from 'class-transformer';
import { IsDateString, IsIn, IsNumber, IsOptional, IsString, Matches, Min, MinLength } from 'class-validator';

const normalizePhone = ({ value }: { value: unknown }) =>
  typeof value === 'string' ? value.replace(/[\s.-]/g, '') : value;

/** Numérotation ivoirienne en vigueur depuis 2021 : 10 chiffres commençant par 0. */
const CI_PHONE_REGEX = /^0\d{9}$/;
const CI_PHONE_MESSAGE = 'Numéro de téléphone invalide (format attendu : 10 chiffres commençant par 0, ex. 0708091011)';

export class CreateEmployeeDto {
  @IsString()
  @MinLength(1)
  lastName!: string;

  @IsString()
  @MinLength(1)
  firstName!: string;

  @IsOptional()
  @IsString()
  gender?: string;

  @IsOptional()
  @IsDateString()
  birthDate?: string;

  @Transform(normalizePhone)
  @Matches(CI_PHONE_REGEX, { message: CI_PHONE_MESSAGE })
  phone!: string;

  @IsOptional()
  @IsString()
  address?: string;

  @IsString()
  @MinLength(1)
  position!: string;

  @IsDateString()
  hireDate!: string;

  @IsOptional()
  @IsString()
  contractType?: string;

  @IsNumber()
  @Min(0.01)
  weeklySalary!: number;

  @IsOptional()
  @IsString()
  team?: string;

  @IsOptional()
  @IsString()
  registrationNumber?: string;

  @IsOptional()
  @IsString()
  notes?: string;
}

export class UpdateEmployeeDto {
  @IsOptional()
  @IsString()
  @MinLength(1)
  lastName?: string;

  @IsOptional()
  @IsString()
  @MinLength(1)
  firstName?: string;

  @IsOptional()
  @IsString()
  gender?: string;

  @IsOptional()
  @IsDateString()
  birthDate?: string;

  @IsOptional()
  @Transform(normalizePhone)
  @Matches(CI_PHONE_REGEX, { message: CI_PHONE_MESSAGE })
  phone?: string;

  @IsOptional()
  @IsString()
  address?: string;

  @IsOptional()
  @IsString()
  @MinLength(1)
  position?: string;

  @IsOptional()
  @IsDateString()
  hireDate?: string;

  @IsOptional()
  @IsString()
  contractType?: string;

  @IsOptional()
  @IsNumber()
  @Min(0.01)
  weeklySalary?: number;

  @IsOptional()
  @IsString()
  team?: string;

  @IsOptional()
  @IsString()
  registrationNumber?: string;

  @IsOptional()
  @IsString()
  notes?: string;

  @IsOptional()
  @IsIn(['active', 'inactive'])
  status?: string;
}
