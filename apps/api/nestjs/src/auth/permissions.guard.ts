import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Request } from 'express';
import { AuthorizationService } from './authorization.service.js';
import { PERMISSIONS_KEY } from './permissions.decorator.js';

/**
 * Enforces @RequirePermissions(...) against the establishment named by the
 * route's `:establishmentId` param. Must run after SupabaseJwtGuard, which
 * populates `request.user`.
 */
@Injectable()
export class PermissionsGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly authorization: AuthorizationService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const required = this.reflector.getAllAndOverride<string[]>(PERMISSIONS_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!required || required.length === 0) return true;

    const request = context.switchToHttp().getRequest<Request>();
    const userId = request.user?.sub;
    const establishmentId = request.params.establishmentId;

    if (!userId || typeof establishmentId !== 'string' || establishmentId.length === 0) {
      throw new ForbiddenException('Établissement ou utilisateur introuvable pour vérifier les permissions');
    }

    const allowed = await this.authorization.hasAllPermissions(userId, establishmentId, required);
    if (!allowed) {
      throw new ForbiddenException(`Permission(s) manquante(s) : ${required.join(', ')}`);
    }
    return true;
  }
}
