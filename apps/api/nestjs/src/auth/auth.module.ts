import { Module } from '@nestjs/common';
import { AuthController } from './auth.controller.js';
import { AuthorizationService } from './authorization.service.js';
import { PermissionsGuard } from './permissions.guard.js';
import { SupabaseJwtGuard } from './supabase-jwt.guard.js';

@Module({
  controllers: [AuthController],
  providers: [SupabaseJwtGuard, PermissionsGuard, AuthorizationService],
  exports: [SupabaseJwtGuard, PermissionsGuard, AuthorizationService],
})
export class AuthModule {}
