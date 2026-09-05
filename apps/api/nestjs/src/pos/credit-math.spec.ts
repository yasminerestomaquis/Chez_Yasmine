import { describe, expect, it } from 'vitest';
import { applyCreditSale, applyRepayment } from './credit-math.js';

describe('applyCreditSale', () => {
  it('increases the balance by the sale amount', () => {
    expect(applyCreditSale({ balance: 1000, limit: 5000 }, 2000)).toBe(3000);
  });

  it('rejects a sale that would exceed the credit limit', () => {
    expect(() => applyCreditSale({ balance: 4000, limit: 5000 }, 2000)).toThrow('plafond de crédit dépassé');
  });

  it('rejects a non-positive sale amount', () => {
    expect(() => applyCreditSale({ balance: 0, limit: 5000 }, 0)).toThrow('montant invalide');
  });
});

describe('applyRepayment', () => {
  it('decreases the balance by the repayment amount', () => {
    expect(applyRepayment(3000, 1000)).toBe(2000);
  });

  it('rejects a repayment larger than the current balance', () => {
    expect(() => applyRepayment(500, 1000)).toThrow('remboursement supérieur au solde');
  });

  it('rejects a non-positive repayment amount', () => {
    expect(() => applyRepayment(1000, 0)).toThrow('montant invalide');
  });
});
