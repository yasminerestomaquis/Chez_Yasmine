import { BadRequestException, ConflictException, ForbiddenException, Injectable } from '@nestjs/common';
import { AuthorizationService } from '../auth/authorization.service.js';
import { SupabaseAdminService } from '../auth/supabase-admin.service.js';
import { PrismaService } from '../prisma/prisma.service.js';
import type { InviteUserDto } from './dto/invite-user.dto.js';

@Injectable()
export class UsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly authorization: AuthorizationService,
    private readonly supabaseAdmin: SupabaseAdminService,
  ) {}

  list(establishmentId: string) {
    return this.prisma.userEstablishmentRole.findMany({
      where: { establishmentId },
      include: { user: { select: { fullName: true } }, role: { select: { id: true, name: true } } },
      orderBy: { createdAt: 'asc' },
    });
  }

  /** Rôles assignables : les rôles système (clonables par toute organisation) + les rôles propres à cette organisation. */
  async listAvailableRoles(establishmentId: string) {
    const establishment = await this.prisma.establishment.findUniqueOrThrow({ where: { id: establishmentId } });
    return this.prisma.role.findMany({
      where: { OR: [{ isSystem: true }, { organizationId: establishment.organizationId }] },
      orderBy: { name: 'asc' },
    });
  }

  /**
   * Envoie une invitation Supabase Auth (lien magique pour choisir un mot de
   * passe) rattachant directement le nouvel utilisateur à `establishmentId`
   * avec `dto.roleId` — voir la migration `20260909120000_admin_invite_bootstrap.sql`
   * pour la partie qui évite qu'une invitation crée une organisation fantôme
   * (comme le ferait une inscription normale).
   *
   * Protection anti-élévation de privilèges : `callerId` ne peut affecter un
   * rôle qui accorde une permission qu'il ne détient pas lui-même sur cet
   * établissement — sinon un Gérant pourrait inviter un pair avec un rôle
   * plus puissant que le sien (ex. Propriétaire).
   */
  async invite(establishmentId: string, callerId: string, dto: InviteUserDto) {
    const role = await this.prisma.role.findFirst({
      where: { id: dto.roleId },
      include: { rolePermissions: { select: { permission: { select: { code: true } } } } },
    });
    if (!role) {
      throw new BadRequestException('Rôle introuvable');
    }
    const establishment = await this.prisma.establishment.findUniqueOrThrow({ where: { id: establishmentId } });
    if (!role.isSystem && role.organizationId !== establishment.organizationId) {
      throw new BadRequestException("Ce rôle n'appartient pas à cette organisation");
    }

    const targetPermissions = role.rolePermissions.map((rp) => rp.permission.code);
    const callerPermissions = await this.authorization.getPermissionCodes(callerId, establishmentId);
    const missing = targetPermissions.filter((code) => !callerPermissions.has(code));
    if (missing.length > 0) {
      throw new ForbiddenException(
        `Vous ne pouvez pas affecter le rôle « ${role.name} » : il accorde des permissions que vous n'avez pas vous-même (${missing.join(', ')})`,
      );
    }

    try {
      await this.supabaseAdmin.inviteUserByEmail(dto.email, {
        invited_establishment_id: establishmentId,
        invited_role_id: dto.roleId,
        full_name: dto.fullName ?? '',
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Échec de l'invitation";
      if (/already.*registered|already.*exists/i.test(message)) {
        throw new ConflictException(
          'Cette adresse e-mail a déjà un compte — rattacher un utilisateur existant à un nouvel établissement n\'est pas encore pris en charge.',
        );
      }
      throw new BadRequestException(`Échec de l'invitation : ${message}`);
    }

    return { email: dto.email, roleId: dto.roleId, roleName: role.name };
  }
}
