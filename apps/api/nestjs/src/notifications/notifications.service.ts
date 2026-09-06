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

  async list(establishmentId: string, userId: string) {
    const organizationId = await this.getOrganizationId(establishmentId, userId);
    return this.prisma.notification.findMany({
      where: { organizationId, OR: [{ userId }, { userId: null }] },
      orderBy: { createdAt: 'desc' },
    });
  }

  async unreadCount(establishmentId: string, userId: string): Promise<number> {
    const organizationId = await this.getOrganizationId(establishmentId, userId);
    return this.prisma.notification.count({
      where: { organizationId, readAt: null, OR: [{ userId }, { userId: null }] },
    });
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
