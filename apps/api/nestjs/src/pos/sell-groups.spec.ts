import { ForbiddenException } from '@nestjs/common';
import { describe, expect, it, vi } from 'vitest';
import type { AuthorizationService } from '../auth/authorization.service.js';
import { sellGroupOf, sellGroupPermissionsOf, sellGroupsOf } from './sell-groups.js';
import { SellGroupsService } from './sell-groups.service.js';

const casier = { hasCasePricing: true, hasVariablePricing: false, isBeverage: false };
const gbele = { hasCasePricing: false, hasVariablePricing: false, isBeverage: true };
const plats = { hasCasePricing: false, hasVariablePricing: true, isBeverage: false };
const ordinaire = { hasCasePricing: false, hasVariablePricing: false, isBeverage: false };

describe('sellGroupOf', () => {
  it('classe les catégories comme les recettes de l’Accueil', () => {
    expect(sellGroupOf(casier)).toBe('beverages');
    expect(sellGroupOf(gbele)).toBe('gbele');
    expect(sellGroupOf(plats)).toBe('plats');
  });

  it('une boisson par casier marquée isBeverage reste « boissons hors Gbêlê »', () => {
    expect(sellGroupOf({ ...casier, isBeverage: true })).toBe('beverages');
  });

  it('catégorie ordinaire ou absente : aucun groupe (seul pos.sell s’applique)', () => {
    expect(sellGroupOf(ordinaire)).toBeNull();
    expect(sellGroupOf(null)).toBeNull();
  });

  it('sellGroupsOf dédoublonne et garde l’ordre', () => {
    expect(sellGroupsOf([{ category: plats }, { category: casier }, { category: plats }, { category: null }])).toEqual([
      'plats',
      'beverages',
    ]);
  });
});

describe('sellGroupPermissionsOf', () => {
  it('ne garde que les codes pos.sell_* accordés', () => {
    expect(sellGroupPermissionsOf(new Set(['pos.sell', 'pos.sell_gbele', 'reports.view']))).toEqual(['pos.sell_gbele']);
  });
});

describe('SellGroupsService.assertCanSell', () => {
  const make = (granted: string[]) => {
    const authorization = { getPermissionCodes: vi.fn().mockResolvedValue(new Set(granted)) };
    return { service: new SellGroupsService(authorization as unknown as AuthorizationService), authorization };
  };

  it('autorise quand toutes les permissions des groupes du panier sont accordées', async () => {
    const { service } = make(['pos.sell_beverages', 'pos.sell_plats']);
    await expect(service.assertCanSell('u', 'e', [{ category: casier }, { category: plats }])).resolves.toBeUndefined();
  });

  it('refuse (403) en nommant le groupe refusé', async () => {
    const { service } = make(['pos.sell_beverages']);
    await expect(service.assertCanSell('u', 'e', [{ category: casier }, { category: plats }])).rejects.toThrow(
      /plats.*pos\.sell_plats/,
    );
    await expect(service.assertCanSell('u', 'e', [{ category: gbele }])).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('un panier sans groupe ne consulte même pas les permissions', async () => {
    const { service, authorization } = make([]);
    await service.assertCanSell('u', 'e', [{ category: ordinaire }, { category: null }]);
    expect(authorization.getPermissionCodes).not.toHaveBeenCalled();
  });
});
