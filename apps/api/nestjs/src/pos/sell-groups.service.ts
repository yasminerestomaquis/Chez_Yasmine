import { ForbiddenException, Injectable } from '@nestjs/common';
import { AuthorizationService } from '../auth/authorization.service.js';
import { SELL_GROUP_LABELS, SELL_GROUP_PERMISSIONS, sellGroupsOf, type CategoryFlags } from './sell-groups.js';

/**
 * Refuse (403) la saisie d'une vente ou d'une ligne d'addition qui touche un
 * groupe de recettes (boissons hors Gbêlê, Gbêlê, plats) que le rôle de
 * l'utilisateur n'a pas le droit de saisir — voir `sell-groups.ts`. S'applique
 * à tous les chemins : Caisse, ajout à une addition, et leur rejeu hors ligne
 * (`SyncService` rappelle les mêmes services avec l'identité de l'auteur).
 */
@Injectable()
export class SellGroupsService {
  constructor(private readonly authorization: AuthorizationService) {}

  async assertCanSell(userId: string, establishmentId: string, products: { category: CategoryFlags | null }[]) {
    const groups = sellGroupsOf(products);
    if (groups.length === 0) return;
    const granted = await this.authorization.getPermissionCodes(userId, establishmentId);
    const missing = groups.filter((group) => !granted.has(SELL_GROUP_PERMISSIONS[group]));
    if (missing.length > 0) {
      throw new ForbiddenException(
        `Saisie non autorisée pour votre rôle : ${missing.map((g) => SELL_GROUP_LABELS[g]).join(', ')} ` +
          `(permission ${missing.map((g) => SELL_GROUP_PERMISSIONS[g]).join(', ')})`,
      );
    }
  }
}
