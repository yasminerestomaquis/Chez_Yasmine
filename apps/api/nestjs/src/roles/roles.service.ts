import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';

@Injectable()
export class RolesService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Matrice complète rôle × permission pour le tableau de bord "Gestion des
   * permissions" (lib/users/permissions_dashboard_page.dart) — demande
   * utilisateur du 2026-09-16, réservé au Super Administrateur (roles.manage,
   * voir supabase/seed/001_roles_permissions.sql). Les rôles édités ici sont
   * globaux ("système", organization_id NULL) : aucune organisation ne les a
   * encore jamais clonés dans cette installation, éditer leurs permissions
   * les affecte partout — même portée que `UsersService.listAvailableRoles`,
   * qui les liste déjà tels quels pour le sélecteur de rôle à l'invitation.
   */
  async listMatrix(establishmentId: string) {
    const establishment = await this.prisma.establishment.findUniqueOrThrow({ where: { id: establishmentId } });
    const [permissions, roles] = await Promise.all([
      this.prisma.permission.findMany({ orderBy: { code: 'asc' } }),
      this.prisma.role.findMany({
        where: { OR: [{ isSystem: true }, { organizationId: establishment.organizationId }] },
        include: { rolePermissions: { select: { permission: { select: { code: true } } } } },
        orderBy: { name: 'asc' },
      }),
    ]);

    return {
      permissions: permissions.map((p) => ({ code: p.code, description: p.description })),
      roles: roles.map((r) => ({
        id: r.id,
        name: r.name,
        isSystem: r.isSystem,
        permissionCodes: r.rolePermissions.map((rp) => rp.permission.code),
      })),
    };
  }

  async grant(establishmentId: string, roleId: string, code: string): Promise<void> {
    const [role, permission] = await Promise.all([
      this.findRoleOrThrow(establishmentId, roleId),
      this.findPermissionOrThrow(code),
    ]);
    await this.prisma.rolePermission.createMany({
      data: [{ roleId: role.id, permissionId: permission.id }],
      skipDuplicates: true,
    });
  }

  /**
   * Refuse deux situations de verrouillage, où plus personne ne pourrait
   * ensuite se réaccorder l'accès nécessaire pour corriger l'erreur :
   * - retirer `roles.manage` au Super Administrateur précisément (message
   *   dédié, le cas le plus probable en pratique) ;
   * - retirer `users.manage`/`roles.manage` à un rôle si, une fois fait, plus
   *   aucun membre réellement affecté (n'importe où) ne porterait plus cette
   *   permission — même principe que
   *   `UsersService.assertKeepsAtLeastOneUserManager`, généralisé ici à
   *   `roles.manage` en plus de `users.manage`.
   */
  async revoke(establishmentId: string, roleId: string, code: string): Promise<void> {
    const [role, permission] = await Promise.all([
      this.findRoleOrThrow(establishmentId, roleId),
      this.findPermissionOrThrow(code),
    ]);

    if (role.name === 'Super Administrateur' && code === 'roles.manage') {
      throw new ConflictException(
        'Impossible de retirer "Gestion des rôles et permissions" au Super Administrateur : ' +
          'plus personne ne pourrait alors accéder à ce tableau de bord pour la lui redonner.',
      );
    }
    if (code === 'users.manage' || code === 'roles.manage') {
      await this.assertKeepsAtLeastOneHolder(code, role.id);
    }

    await this.prisma.rolePermission.deleteMany({ where: { roleId: role.id, permissionId: permission.id } });
  }

  private async findRoleOrThrow(establishmentId: string, roleId: string) {
    const establishment = await this.prisma.establishment.findUniqueOrThrow({ where: { id: establishmentId } });
    const role = await this.prisma.role.findFirst({
      where: { id: roleId, OR: [{ isSystem: true }, { organizationId: establishment.organizationId }] },
    });
    if (!role) throw new NotFoundException('Rôle introuvable pour cet établissement');
    return role;
  }

  private async findPermissionOrThrow(code: string) {
    const permission = await this.prisma.permission.findUnique({ where: { code } });
    if (!permission) throw new NotFoundException(`Permission "${code}" introuvable`);
    return permission;
  }

  private async assertKeepsAtLeastOneHolder(code: string, excludingRoleId: string): Promise<void> {
    const remaining = await this.prisma.userEstablishmentRole.count({
      where: {
        roleId: { not: excludingRoleId },
        role: { rolePermissions: { some: { permission: { code } } } },
      },
    });
    if (remaining === 0) {
      const what = code === 'users.manage' ? 'gérer les utilisateurs' : 'gérer les rôles et permissions';
      throw new ConflictException(`Impossible : plus personne ne pourrait alors ${what}, nulle part dans l'application.`);
    }
  }
}
