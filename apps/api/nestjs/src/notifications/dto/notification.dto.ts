import { IsOptional, IsString, IsUUID, MinLength } from 'class-validator';

export class BroadcastNotificationDto {
  @IsString()
  @MinLength(1)
  title!: string;

  @IsOptional()
  @IsString()
  body?: string;

  /** Omitted = broadcast to the whole organization; given = targeted to one user (must belong to the same organization). */
  @IsOptional()
  @IsUUID()
  userId?: string;
}
