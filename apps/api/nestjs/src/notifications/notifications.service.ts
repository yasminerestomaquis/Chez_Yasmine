import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import { StockMovementsService } from '../stock/stock-movements.service.js';
import type { BroadcastNotificationDto } from './dto/notification.dto.js';

@Injectable()
export class NotificationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly stockMovements: StockMovementsService,
  ) {}

  /**
   * Notification is organization-scoped (Phase 3 schema), but every route in
   * this app is establishment-scoped — this resolves one to the other and,
   * as a side effect, is the membership check: list/unreadCount/markAsRead
   * carry no @RequirePermissions (any establishment member may read their
   * own notifications, like GET /auth/me), so this is what actually stops a
   * user unaffiliated with the establishment from reading another
   * organization's notifications.
   */
  private async getOrganizationId(establishmentId: string, userId: string): Promise<string> {
    const membership = await this.prisma.userEstablishmentRole.findFirst({
      where: { userId, establishmentId },
      select: { establishment: { select: { organizationId: true } } },
    });
    if (!membership) {
      throw new ForbiddenException("Vous n'êtes pas membre de cet établissement");
    }
    return membership.establishment.organizationId;
  }

  /**
   * Marque aussi la liste comme "vue à l'instant" (`UserProfile.notificationsViewedAt`)
   * — c'est ce qui fait disparaître le badge "9+" de l'accueil après avoir
   * simplement ouvert cet écran, sans avoir à ouvrir chaque notification une
   * par une (demande utilisateur du 2026-09-13). Voir `unreadCount` pour
   * comment ce champ est utilisé, et pourquoi c'est nécessaire pour les
   * diffusions (`readAt` y est partagé par toute l'organisation, donc ne
   * peut pas servir de marqueur "vu par MOI").
   */
  async list(establishmentId: string, userId: string) {
    const organizationId = await this.getOrganizationId(establishmentId, userId);
    const [notifications] = await Promise.all([
      this.prisma.notification.findMany({
        where: { organizationId, OR: [{ userId }, { userId: null }] },
        orderBy: { createdAt: 'desc' },
      }),
      this.prisma.userProfile.update({ where: { id: userId }, data: { notificationsViewedAt: new Date() } }),
    ]);
    return notifications;
  }

  /**
   * Une notification apparue avant la dernière consultation de la liste
   * (`notificationsViewedAt`) ne compte plus dans le badge — que
   * l'utilisateur l'ait ouverte individuellement ou non. `notificationsViewedAt`
   * `null` (jamais consultée) équivaut à "depuis toujours" : tout compte,
   * comportement inchangé pour un utilisateur qui n'a encore jamais ouvert
   * l'écran Notifications.
   */
  async unreadCount(establishmentId: string, userId: string): Promise<number> {
    const organizationId = await this.getOrganizationId(establishmentId, userId);
    const profile = await this.prisma.userProfile.findUnique({ where: { id: userId }, select: { notificationsViewedAt: true } });
    return this.prisma.notification.count({
      where: {
        organizationId,
        readAt: null,
        createdAt: { gt: profile?.notificationsViewedAt ?? new Date(0) },
        OR: [{ userId }, { userId: null }],
      },
    });
  }

  /** Réservé au Super Administrateur (voir NotificationsController.clearAll) — efface toutes les notifications de l'organisation, ciblées ou diffusées, sans distinction. */
  async clearAll(establishmentId: string, callerId: string): Promise<void> {
    const organizationId = await this.getOrganizationId(establishmentId, callerId);
    await this.prisma.notification.deleteMany({ where: { organizationId } });
  }

  /**
   * Only a notification targeted at this exact user can be marked read — a
   * broadcast row (userId null) has a single shared readAt, so marking it
   * read for one person would mark it read for the whole organization.
   * Documented limitation rather than a per-user read-state table that
   * doesn't exist in the schema.
   */
  async markAsRead(establishmentId: string, userId: string, notificationId: string) {
    await this.getOrganizationId(establishmentId, userId);
    const { count } = await this.prisma.notification.updateMany({
      where: { id: notificationId, userId },
      data: { readAt: new Date() },
    });
    if (count === 0) {
      throw new NotFoundException("Notification introuvable, ou non adressée à cet utilisateur");
    }
  }

  async broadcast(establishmentId: string, callerId: string, dto: BroadcastNotificationDto) {
    const organizationId = await this.getOrganizationId(establishmentId, callerId);
    if (dto.userId) {
      const targetMembership = await this.prisma.userEstablishmentRole.findFirst({
        where: { userId: dto.userId, establishment: { organizationId } },
      });
      if (!targetMembership) {
        throw new BadRequestException("L'utilisateur ciblé n'appartient pas à cette organisation");
      }
    }
    return this.prisma.notification.create({
      data: { organizationId, userId: dto.userId, title: dto.title, body: dto.body },
    });
  }

  /**
   * Not wired to any scheduler — this environment has none configured (see
   * PROJECT_PLAN.md). Meant to be called on demand for now, and by a real
   * cron once one exists, without changing this method's contract.
   * Idempotent-ish: skips a product that already has an unread low-stock
   * notification, so repeated calls don't pile up duplicates.
   */
  async generateLowStockAlerts(establishmentId: string, callerId: string) {
    const organizationId = await this.getOrganizationId(establishmentId, callerId);
    const alerts = await this.stockMovements.listLowStockAlerts(establishmentId);

    const created = [];
    for (const alert of alerts) {
      const title = `Stock bas : ${alert.name}`;
      const existing = await this.prisma.notification.findFirst({
        where: { organizationId, userId: null, title, readAt: null },
      });
      if (existing) continue;
      created.push(
        await this.prisma.notification.create({
          data: {
            organizationId,
            title,
            body: `Quantité actuelle : ${alert.stockQuantity} (seuil : ${alert.minStock})`,
          },
        }),
      );
    }
    return created;
  }
}
