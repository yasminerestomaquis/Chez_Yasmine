import { describe, expect, it } from 'vitest';
import { HOME_BREAKDOWN_FIELD_PERMISSIONS, HOME_PERMISSIONS, canViewHome, homePermissionsOf, maskBreakdown } from './home-permissions.js';

const breakdown = {
  totalRevenue: 54950,
  cashRevenue: 48250,
  mobileMoneyRevenue: 6700,
  boissonsSansGbeleRevenue: 12500,
  gbeleRevenue: 1000,
  platsRevenue: 41450,
  boissonsSansGbeleCash: 11300,
  boissonsSansGbeleMobileMoney: 1200,
  gbeleCash: 1000,
  gbeleMobileMoney: 0,
  platsCash: 35950,
  platsMobileMoney: 5500,
};

describe('home-permissions', () => {
  it('compte 14 rubriques, toutes préfixées home.', () => {
    expect(HOME_PERMISSIONS).toHaveLength(14);
    expect(HOME_PERMISSIONS.every((c) => c.startsWith('home.'))).toBe(true);
  });

  it('homePermissionsOf ne garde que les codes Accueil accordés', () => {
    const granted = new Set(['home.cash', 'home.revenue_plats', 'reports.view', 'pos.sell']);
    expect(homePermissionsOf(granted)).toEqual(['home.cash', 'home.revenue_plats']);
  });

  it('canViewHome : vrai dès qu’une rubrique est accordée', () => {
    expect(canViewHome(new Set(['home.orders']))).toBe(true);
    expect(canViewHome(new Set(['reports.view', 'pos.sell']))).toBe(false);
  });

  it('chaque champ du détail dépend d’un code Accueil existant', () => {
    for (const code of Object.values(HOME_BREAKDOWN_FIELD_PERMISSIONS)) {
      expect(HOME_PERMISSIONS).toContain(code);
    }
  });
});

describe('maskBreakdown', () => {
  it('rôle « Serveur » par défaut : seules les recettes boissons sans Gbêlê / Gbêlê et leur détail sortent', () => {
    const serveur = new Set([
      'home.revenue_beverages',
      'home.revenue_gbele',
      'home.detail_beverages_cash',
      'home.detail_beverages_mobile',
      'home.detail_gbele_cash',
      'home.detail_gbele_mobile',
    ]);
    expect(maskBreakdown(breakdown, serveur)).toEqual({
      ...breakdown,
      totalRevenue: 0,
      cashRevenue: 0,
      mobileMoneyRevenue: 0,
      platsRevenue: 0,
      platsCash: 0,
      platsMobileMoney: 0,
    });
  });

  it('tout accordé : rien n’est masqué ; rien accordé : tout est à 0 ; l’entrée n’est pas modifiée', () => {
    expect(maskBreakdown(breakdown, new Set(HOME_PERMISSIONS))).toEqual(breakdown);
    const none = maskBreakdown(breakdown, new Set());
    expect(Object.values(none).every((v) => v === 0)).toBe(true);
    expect(breakdown.totalRevenue).toBe(54950);
  });
});
