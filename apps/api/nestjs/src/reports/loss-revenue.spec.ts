import { Decimal } from '@prisma/client';
import { describe, expect, it } from 'vitest';
import { lossGroupOf, lossRevenueByGroup, lossUnitSalePrice } from './loss-revenue.js';

const D = (n: number) => new Decimal(n);
const cat = (o: Partial<{ hasCasePricing: boolean; hasVariablePricing: boolean; isBeverage: boolean }>) => ({
  hasCasePricing: false,
  hasVariablePricing: false,
  isBeverage: false,
  ...o,
});

describe('loss-revenue', () => {
  it('classe Boissons (casier ou boisson), Plats (prix variable) ou aucun groupe', () => {
    expect(lossGroupOf(cat({ hasCasePricing: true }))).toBe('boissons');
    expect(lossGroupOf(cat({ isBeverage: true }))).toBe('boissons');
    expect(lossGroupOf(cat({ hasVariablePricing: true }))).toBe('plats');
    expect(lossGroupOf(cat({}))).toBeNull();
    expect(lossGroupOf(null)).toBeNull();
  });

  it('prix de vente, sinon prix de référence, sinon 0', () => {
    expect(lossUnitSalePrice({ salePrice: D(500), referenceSalePrice: D(4000), category: null })).toBe(500);
    expect(lossUnitSalePrice({ salePrice: null, referenceSalePrice: D(4000), category: null })).toBe(4000);
    expect(lossUnitSalePrice({ salePrice: null, referenceSalePrice: null, category: null })).toBe(0);
  });

  it('cumule quantité × prix de vente par groupe et ignore les produits hors groupe', () => {
    const totals = lossRevenueByGroup([
      { quantity: D(3), product: { salePrice: D(500), referenceSalePrice: null, category: cat({ hasCasePricing: true }) } },
      { quantity: D(1.5), product: { salePrice: null, referenceSalePrice: D(4000), category: cat({ isBeverage: true }) } },
      { quantity: D(2), product: { salePrice: D(1000), referenceSalePrice: null, category: cat({ hasVariablePricing: true }) } },
      { quantity: D(9), product: { salePrice: D(700), referenceSalePrice: null, category: cat({}) } },
    ]);

    expect(totals).toEqual({ boissons: 7500, plats: 2000 });
  });
});
