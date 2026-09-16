import { Controller, Delete, Get, HttpCode, HttpStatus, Param, Put, UseGuards } from '@nestjs/common';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { RolesService } from './roles.service.js';

/**
 * Tableau de bord "Gestion des permissions" (module Utilisateurs, demande
 * utilisateur du 2026-09-16) — `roles.manage`, réservée au Super
 * Administrateur (voir supabase/seed/001_roles_permissions.sql). Distinct de
 * `UsersController` (`users.manage`) : gérer QUI a accès à l'établissement
 * n'est pas la même permission que décider CE QUE chaque rôle peut faire.
 */
@Controller('establishments/:establishmentId')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
@RequirePermissions('roles.manage')
export class RolesController {
  constructor(private readonly roles: RolesService) {}

  @Get('roles-permissions')
  listMatrix(@Param('establishmentId') establishmentId: string) {
    return this.roles.listMatrix(establishmentId);
  }

  @Put('roles/:roleId/permissions/:code')
  @HttpCode(HttpStatus.NO_CONTENT)
  grant(@Param('establishmentId') establishmentId: string, @Param('roleId') roleId: string, @Param('code') code: string) {
    return this.roles.grant(establishmentId, roleId, code);
  }

  @Delete('roles/:roleId/permissions/:code')
  @HttpCode(HttpStatus.NO_CONTENT)
  revoke(@Param('establishmentId') establishmentId: string, @Param('roleId') roleId: string, @Param('code') code: string) {
    return this.roles.revoke(establishmentId, roleId, code);
  }
}
