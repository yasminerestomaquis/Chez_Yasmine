import { describe, expect, it } from 'vitest';
import { computeCartTotals, validatePayments, type CartLine, type PaymentInput } from './pos-math.js';

const lines: CartLine[] = [
  { productId: 'p1', unitPrice: 1000, quantity: 3 },
  { productId: 'p2', unitPrice: 1500, quantity: 2 },
];

describe('computeCartTotals', () => {
  it('sums line totals into a subtotal', () => {
    expect(computeCartTotals(lines, { type: 'amount', value: 0 }).subtotal).toBe(6000);
  });

  it('applies a fixed-amount discount', () => {
    const totals = computeCartTotals(lines, { type: 'amount', value: 500 });
    expect(totals.discount).toBe(500);
    expect(totals.total).toBe(5500);
  });

  it('applies a percentage discount', () => {
    const totals = computeCartTotals(lines, { type: 'percent', value: 10 });
    expect(totals.discount).toBe(600);
    expect(totals.total).toBe(5400);
  });

  it('never lets a discount push the total below zero', () => {
    const totals = computeCartTotals(lines, { type: 'amount', value: 999999 });
    expect(totals.total).toBe(0);
    expect(totals.discount).toBe(6000);
  });

  it('rejects a negative or zero quantity', () => {
    const badLines: CartLine[] = [{ productId: 'p1', unitPrice: 1000, quantity: 0 }];
    expect(() => computeCartTotals(badLines, { type: 'amount', value: 0 })).toThrow('quantité invalide');
  });

  it('rejects an empty cart', () => {
    expect(() => computeCartTotals([], { type: 'amount', value: 0 })).toThrow('panier est vide');
  });
});

describe('validatePayments', () => {
  it('accepts a single cash payment matching the total exactly', () => {
    const payments: PaymentInput[] = [{ method: 'cash', amount: 5000 }];
    expect(() => validatePayments(payments, 5000)).not.toThrow();
  });

  it('accepts a mixed payment that sums to the total', () => {
    const payments: PaymentInput[] = [
      { method: 'cash', amount: 2000 },
      { method: 'mobile_money', amount: 3000 },
    ];
    expect(() => validatePayments(payments, 5000)).not.toThrow();
  });

  it('rejects an incomplete payment', () => {
    expect(() => validatePayments([{ method: 'cash', amount: 4000 }], 5000)).toThrow('paiement incomplet');
  });

  it('rejects a payment that overshoots the total', () => {
    expect(() => validatePayments([{ method: 'cash', amount: 6000 }], 5000)).toThrow('paiement incomplet');
  });

  it('rejects a payment with no lines', () => {
    expect(() => validatePayments([], 5000)).toThrow('paiement incomplet');
  });

  it('rejects a negative payment amount', () => {
    expect(() => validatePayments([{ method: 'cash', amount: -100 }], 5000)).toThrow('montant invalide');
  });

  it('requires a customer for credit payments', () => {
    const payments: PaymentInput[] = [{ method: 'credit', amount: 5000 }];
    expect(() => validatePayments(payments, 5000)).toThrow('client requis');
    expect(() => validatePayments(payments, 5000, { customerId: undefined })).toThrow('client requis');
    expect(() => validatePayments(payments, 5000, { customerId: 'c1' })).not.toThrow();
  });
});
