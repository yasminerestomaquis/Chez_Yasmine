import { IsEmail, IsOptional, IsString, IsUUID, MinLength } from 'class-validator';

export class InviteUserDto {
  @IsEmail()
  email!: string;

  @IsUUID()
  roleId!: string;

  @IsOptional()
  @IsString()
  @MinLength(1)
  fullName?: string;
}
