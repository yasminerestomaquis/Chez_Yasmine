import { createParamDecorator, type ExecutionContext } from '@nestjs/common';
import type { Request } from 'express';
import type { SupabaseUser } from './supabase-jwt.guard.js';

/**
 * Extracts the Supabase user attached to the request by SupabaseJwtGuard.
 * Only valid on routes protected by that guard.
 */
export const CurrentUser = createParamDecorator((_data: unknown, ctx: ExecutionContext): SupabaseUser => {
  const request = ctx.switchToHttp().getRequest<Request>();
  return request.user as SupabaseUser;
});
