import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';

/**
 * Notifie toute l'organisation d'une saisie effectuée par un utilisateur,
 * pour les actions financières/stock jugées clés (voir docs/api/notifications.md) :
 * ventes, achats reçus, dépenses, pertes, mouvements de stock manuels,
 * clôtures de caisse — pas les modifications mineures de catalogue.
 *
 * Volontairement dans son propre module, sans dépendre de
 * `NotificationsService` ni en être dépendu : ce dernier dépend déjà de
 * `StockModule` (pour les alertes de stock bas), et `StockModule` doit
 * pouvoir notifier lui aussi — les faire dépendre l'un de l'autre créerait
 * un cycle de modules. Cette classe ne fait qu'écrire une notification
 * broadcast (`userId: null`, visible par toute l'organisation), sans les
 * autres responsabilités (lecture, marquage lu) de `NotificationsService`.
 */
@Injectable()
export class ActivityNotifierService {
  private readonly logger = new Logger(ActivityNotifierService.name);

  constructor(private readonly prisma: PrismaService) {}

  async notify(establishmentId: string, title: string, body: string): Promise<void> {
    const establishment = await this.prisma.establishment.findUnique({
      where: { id: establishmentId },
      select: { organizationId: true },
    });
    if (!establishment) {
      // Ne devrait jamais arriver : establishmentId a déjà été validé par
      // l'appelant avant que l'action métier n'aboutisse. Une notification
      // manquée n'est pas une raison de faire échouer l'action elle-même.
      this.logger.warn(`Notification ignorée : établissement introuvable (${establishmentId})`);
      return;
    }
    await this.prisma.notification.create({
      data: { organizationId: establishment.organizationId, title, body },
    });
  }
}
