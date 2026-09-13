import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { AuthorizationService } from '../auth/authorization.service.js';
import { SupabaseAdminService } from '../auth/supabase-admin.service.js';
import { PrismaService } from '../prisma/prisma.service.js';
import type { InviteUserDto } from './dto/invite-user.dto.js';
import type { UpdateMemberDto } from './dto/update-member.dto.js';

const ROLE_WITH_PERMISSIONS_INCLUDE = {
  rolePermissions: { select: { permission: { select: { code: true } } } },
} as const;

/** En dessous de ce délai depuis `lastSeenAt`, un membre est considéré "en ligne" — voir SupabaseJwtGuard.recordLastSeen et docs/api/users.md. */
const ONLINE_THRESHOLD_MS = 2 * 60_000;

type RoleWithPermissions = { id: string; name: string; isSystem: boolean; organizationId: string | null } & {
  rolePermissions: { permission: { code: string } }[];
};

@Injectable()
export class UsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly authorization: AuthorizationService,
    private readonly supabaseAdmin: SupabaseAdminService,
  ) {}

  /**
   * E-mail et statut de connexion ajoutés le 2026-09-13 (demande
   * utilisateur) — voir docs/api/users.md pour le détail du calcul
   * "en ligne" / "hors ligne depuis" et pourquoi l'e-mail vient de l'API
   * Admin de Supabase plutôt que du schéma Prisma.
   */
  async list(establishmentId: string) {
    const memberships = await this.prisma.userEstablishmentRole.findMany({
      where: { establishmentId },
      include: {
        user: { select: { id: true, fullName: true, lastSeenAt: true } },
        role: { select: { id: true, name: true } },
      },
      orderBy: { createdAt: 'asc' },
    });

    const uniqueUserIds = [...new Set(memberships.map((m) => m.user.id))];
    const emailsById = await this.supabaseAdmin.getEmailsByIds(uniqueUserIds);
    const now = Date.now();

    return memberships.map((m) => {
      const lastSeenAt = m.user.lastSeenAt;
      const isOnline = lastSeenAt != null && now - lastSeenAt.getTime() < ONLINE_THRESHOLD_MS;
      return {
        ...m,
        user: {
          ...m.user,
          email: emailsById.get(m.user.id) ?? null,
          isOnline,
        },
      };
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
   */
  async invite(establishmentId: string, callerId: string, dto: InviteUserDto) {
    const role = await this.assertRoleAssignable(establishmentId, callerId, dto.roleId);
    try {
      await this.supabaseAdmin.inviteUserByEmail(dto.email, this.inviteMetadata(establishmentId, dto));
    } catch (error) {
      throw this.translateSupabaseError(error);
    }
    return { email: dto.email, roleId: dto.roleId, roleName: role.name };
  }

  /**
   * Même effet que invite() (même vérifications, même rattachement) mais
   * sans passer par le service d'e-mail de Supabase (quota gratuit partagé
   * très limité — voir docs/api/users.md) : renvoie le lien d'invitation,
   * à copier/transmettre par l'appelant lui-même (WhatsApp, SMS, son propre
   * e-mail...) — jamais envoyé par le serveur à sa place.
   */
  async generateInviteLink(establishmentId: string, callerId: string, dto: InviteUserDto) {
    const role = await this.assertRoleAssignable(establishmentId, callerId, dto.roleId);
    let link: string;
    try {
      link = await this.supabaseAdmin.generateInviteLink(dto.email, this.inviteMetadata(establishmentId, dto));
    } catch (error) {
      throw this.translateSupabaseError(error);
    }
    return { email: dto.email, roleId: dto.roleId, roleName: role.name, link };
  }

  /**
   * Retire un utilisateur de cet établissement (supprime son affectation de
   * rôle) — ne touche jamais à son compte Supabase Auth lui-même, qui peut
   * appartenir à d'autres établissements. Refuse : de se retirer soi-même, de
   * retirer quelqu'un dont le rôle accorde une permission que l'appelant n'a
   * pas lui-même (même protection anti-élévation que l'invitation, appliquée
   * ici en sens inverse), et de retirer le dernier membre pouvant encore
   * gérer les utilisateurs de cet établissement (ce qui rendrait le module
   * Utilisateurs définitivement inaccessible pour tout le monde).
   */
  async removeMember(establishmentId: string, callerId: string, membershipId: string): Promise<void> {
    const membership = await this.findMembershipOrThrow(establishmentId, membershipId);
    if (membership.userId === callerId) {
      throw new BadRequestException('Vous ne pouvez pas vous retirer vous-même de cet établissement');
    }
    await this.assertCallerOutranks(establishmentId, callerId, membership.role);
    if (this.hasPermission(membership.role, 'users.manage')) {
      await this.assertKeepsAtLeastOneUserManager(establishmentId, membershipId);
    }
    await this.prisma.userEstablishmentRole.delete({ where: { id: membershipId } });
  }

  /**
   * Modifie le rôle et/ou le nom complet d'un membre déjà en place — les
   * deux champs sont indépendants et optionnels. Seul le changement de rôle
   * est soumis à la protection anti-élévation (l'appelant doit dominer, au
   * sens des permissions, à la fois le rôle actuel et le nouveau rôle —
   * sinon un Gérant pourrait par exemple rétrograder un Propriétaire sans
   * avoir lui-même ce niveau d'accès) et à l'interdiction de se modifier
   * soi-même (évite un verrouillage accidentel) ; changer uniquement son
   * propre nom complet est sans risque et reste autorisé.
   */
  async updateMember(establishmentId: string, callerId: string, membershipId: string, dto: UpdateMemberDto) {
    const membership = await this.findMembershipOrThrow(establishmentId, membershipId);

    if (dto.roleId !== undefined) {
      if (membership.userId === callerId) {
        throw new BadRequestException('Vous ne pouvez pas modifier votre propre rôle');
      }
      await this.assertCallerOutranks(establishmentId, callerId, membership.role);
      const newRole = await this.assertRoleAssignable(establishmentId, callerId, dto.roleId);
      if (this.hasPermission(membership.role, 'users.manage') && !this.hasPermission(newRole, 'users.manage')) {
        await this.assertKeepsAtLeastOneUserManager(establishmentId, membershipId);
      }
      await this.prisma.userEstablishmentRole.update({ where: { id: membershipId }, data: { roleId: dto.roleId } });
    }

    if (dto.fullName !== undefined) {
      await this.prisma.userProfile.update({ where: { id: membership.userId }, data: { fullName: dto.fullName } });
    }

    return this.prisma.userEstablishmentRole.findUniqueOrThrow({
      where: { id: membershipId },
      include: { user: { select: { fullName: true } }, role: { select: { id: true, name: true } } },
    });
  }

  /**
   * Génère un lien de réinitialisation de mot de passe pour un membre déjà
   * en place (mot de passe oublié, ou — comme pour missakey1@gmail.com le
   * 2026-09-09 — un mot de passe initial que le Propriétaire ne connaît
   * pas). Même protection anti-élévation que retirer/changer de rôle : sans
   * elle, un Gérant pourrait générer un lien pour un Propriétaire, ce qui
   * revient à pouvoir se connecter à sa place jusqu'à ce qu'il change son
   * mot de passe. Jamais Claude qui envoie ce lien — toujours l'appelant,
   * par le canal de son choix (voir docs/api/users.md).
   */
  async generateRecoveryLink(establishmentId: string, callerId: string, membershipId: string): Promise<{ link: string }> {
    const membership = await this.findMembershipOrThrow(establishmentId, membershipId);
    await this.assertCallerOutranks(establishmentId, callerId, membership.role);
    try {
      const link = await this.supabaseAdmin.generateRecoveryLink(membership.userId);
      return { link };
    } catch (error) {
      throw this.translateSupabaseError(error);
    }
  }

  private async findMembershipOrThrow(establishmentId: string, membershipId: string) {
    const membership = await this.prisma.userEstablishmentRole.findFirst({
      where: { id: membershipId, establishmentId },
      include: { role: { include: ROLE_WITH_PERMISSIONS_INCLUDE } },
    });
    if (!membership) {
      throw new NotFoundException('Utilisateur introuvable pour cet établissement');
    }
    return membership;
  }

  private hasPermission(role: RoleWithPermissions, code: string): boolean {
    return role.rolePermissions.some((rp) => rp.permission.code === code);
  }

  private async assertKeepsAtLeastOneUserManager(establishmentId: string, excludingMembershipId: string): Promise<void> {
    const remaining = await this.prisma.userEstablishmentRole.count({
      where: {
        establishmentId,
        id: { not: excludingMembershipId },
        role: { rolePermissions: { some: { permission: { code: 'users.manage' } } } },
      },
    });
    if (remaining === 0) {
      throw new ConflictException(
        'Impossible : il ne resterait plus personne pouvant gérer les utilisateurs sur cet établissement',
      );
    }
  }

  private inviteMetadata(establishmentId: string, dto: InviteUserDto): Record<string, string | boolean> {
    return {
      invited_establishment_id: establishmentId,
      invited_role_id: dto.roleId,
      full_name: dto.fullName ?? '',
      // Levé par SetPasswordPage (apps/web/flutter/lib/auth/) une fois que
      // la personne invitée a choisi un mot de passe — jusque-là, AuthGate
      // affiche cet écran plutôt que l'application (elle est connectée via
      // le lien à usage unique, mais n'a encore aucun moyen de se
      // reconnecter ensuite).
      needs_password_setup: true,
    };
  }

  private translateSupabaseError(error: unknown): ConflictException | BadRequestException {
    const message = error instanceof Error ? error.message : "Échec de l'invitation";
    if (/already.*registered|already.*exists/i.test(message)) {
      return new ConflictException(
        "Cette adresse e-mail a déjà un compte — rattacher un utilisateur existant à un nouvel établissement n'est pas encore pris en charge.",
      );
    }
    return new BadRequestException(`Échec de l'invitation : ${message}`);
  }

  /**
   * Protection anti-élévation de privilèges : `callerId` ne peut affecter un
   * rôle qui accorde une permission qu'il ne détient pas lui-même sur cet
   * établissement — sinon un Gérant pourrait inviter un pair avec un rôle
   * plus puissant que le sien (ex. Propriétaire).
   */
  private async assertRoleAssignable(establishmentId: string, callerId: string, roleId: string): Promise<RoleWithPermissions> {
    const role = await this.prisma.role.findFirst({ where: { id: roleId }, include: ROLE_WITH_PERMISSIONS_INCLUDE });
    if (!role) {
      throw new BadRequestException('Rôle introuvable');
    }
    const establishment = await this.prisma.establishment.findUniqueOrThrow({ where: { id: establishmentId } });
    if (!role.isSystem && role.organizationId !== establishment.organizationId) {
      throw new BadRequestException("Ce rôle n'appartient pas à cette organisation");
    }
    await this.assertCallerOutranks(establishmentId, callerId, role);
    return role;
  }

  /** Le cœur de la protection anti-élévation, réutilisé pour affecter un rôle comme pour en retirer un. */
  private async assertCallerOutranks(establishmentId: string, callerId: string, role: RoleWithPermissions): Promise<void> {
    const targetPermissions = role.rolePermissions.map((rp) => rp.permission.code);
    const callerPermissions = await this.authorization.getPermissionCodes(callerId, establishmentId);
    const missing = targetPermissions.filter((code) => !callerPermissions.has(code));
    if (missing.length > 0) {
      throw new ForbiddenException(
        `Vous ne pouvez pas affecter ou retirer le rôle « ${role.name} » : il accorde des permissions que vous n'avez pas vous-même (${missing.join(', ')})`,
      );
    }
  }
}
