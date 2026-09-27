import { Decimal } from '@prisma/client';
import { describe, expect, it } from 'vitest';
import { lossUnitSalePrice } from './loss-revenue.js';

const D = (n: number) => new Decimal(n);

describe('loss-revenue', () => {
  it('prix de vente, sinon prix de référence, sinon 0', () => {
    expect(lossUnitSalePrice({ salePrice: D(500), referenceSalePrice: D(4000), category: null })).toBe(500);
    expect(lossUnitSalePrice({ salePrice: null, referenceSalePrice: D(4000), category: null })).toBe(4000);
    expect(lossUnitSalePrice({ salePrice: null, referenceSalePrice: null, category: null })).toBe(0);
  });
});
