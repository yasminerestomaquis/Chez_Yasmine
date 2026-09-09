import { Module } from '@nestjs/common';
import { AuthController } from './auth.controller.js';
import { AuthorizationService } from './authorization.service.js';
import { PermissionsGuard } from './permissions.guard.js';
import { SupabaseAdminService } from './supabase-admin.service.js';
import { SupabaseJwtGuard } from './supabase-jwt.guard.js';

@Module({
  controllers: [AuthController],
  providers: [SupabaseJwtGuard, PermissionsGuard, AuthorizationService, SupabaseAdminService],
  exports: [SupabaseJwtGuard, PermissionsGuard, AuthorizationService, SupabaseAdminService],
})
export class AuthModule {}
