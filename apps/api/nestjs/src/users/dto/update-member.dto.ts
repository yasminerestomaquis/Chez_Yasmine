import { IsOptional, IsString, IsUUID, MinLength } from 'class-validator';

export class UpdateMemberDto {
  @IsOptional()
  @IsUUID()
  roleId?: string;

  @IsOptional()
  @IsString()
  @MinLength(1)
  fullName?: string;
}
