import { Controller, Get, NotFoundException, Param, UseGuards } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import { CurrentUser } from './current-user.decorator.js';
import { RequirePermissions } from './permissions.decorator.js';
import { PermissionsGuard } from './permissions.guard.js';
import type { SupabaseUser } from './supabase-jwt.guard.js';
import { SupabaseJwtGuard } from './supabase-jwt.guard.js';

@Controller()
@UseGuards(SupabaseJwtGuard)
export class AuthController {
  constructor(private readonly prisma: PrismaService) {}

  /** The authenticated user's profile and the establishments they have a role on. */
  @Get('auth/me')
  async me(@CurrentUser() user: SupabaseUser) {
    const profile = await this.prisma.userProfile.findUnique({
      where: { id: user.sub },
      include: {
        establishmentRoles: {
          include: { establishment: true, role: true },
        },
      },
    });

    if (!profile) {
      throw new NotFoundException("Profil utilisateur introuvable — l'inscription a peut-être échoué avant la création du profil");
    }

    return {
      id: profile.id,
      email: user.email,
      fullName: profile.fullName,
      organizationId: profile.organizationId,
      establishments: profile.establishmentRoles.map((link) => ({
        id: link.establishment.id,
        name: link.establishment.name,
        role: link.role.name,
      })),
    };
  }

  /**
   * Demo route proving SupabaseJwtGuard + PermissionsGuard compose correctly.
   * Not a real feature — remove once a genuine settings endpoint exists.
   */
  @Get('auth/establishments/:establishmentId/ping')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('settings.manage')
  ping(@Param('establishmentId') establishmentId: string) {
    return { ok: true, establishmentId };
  }
}
