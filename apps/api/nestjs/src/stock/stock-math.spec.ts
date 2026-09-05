import { describe, expect, it } from 'vitest';
import { applyStockMovement, isLowStock } from './stock-math.js';

describe('applyStockMovement', () => {
  it('increases quantity for an "in" movement', () => {
    expect(applyStockMovement(10, { type: 'in', quantity: 5 })).toBe(15);
  });

  it('decreases quantity for an "out" movement', () => {
    expect(applyStockMovement(10, { type: 'out', quantity: 4 })).toBe(6);
  });

  it('decreases quantity for a "loss" movement', () => {
    expect(applyStockMovement(10, { type: 'loss', quantity: 2 })).toBe(8);
  });

  it('sets quantity directly for an "adjustment" movement', () => {
    expect(applyStockMovement(10, { type: 'adjustment', quantity: 7 })).toBe(7);
  });

  it('rejects an "out" movement that would drive stock negative', () => {
    expect(() => applyStockMovement(3, { type: 'out', quantity: 5 })).toThrow('stock insuffisant');
  });

  it('rejects a "loss" movement that would drive stock negative', () => {
    expect(() => applyStockMovement(1, { type: 'loss', quantity: 2 })).toThrow('stock insuffisant');
  });

  it('rejects a negative movement quantity', () => {
    expect(() => applyStockMovement(10, { type: 'in', quantity: -1 })).toThrow('quantité invalide');
  });

  it('rejects a non-finite movement quantity', () => {
    expect(() => applyStockMovement(10, { type: 'in', quantity: Number.NaN })).toThrow('quantité invalide');
  });

  it('allows an adjustment down to zero even though it is not additive', () => {
    expect(applyStockMovement(10, { type: 'adjustment', quantity: 0 })).toBe(0);
  });
});

describe('isLowStock', () => {
  it('flags stock at or below the alert threshold', () => {
    expect(isLowStock(5, 5)).toBe(true);
    expect(isLowStock(4, 5)).toBe(true);
  });

  it('does not flag stock above the alert threshold', () => {
    expect(isLowStock(6, 5)).toBe(false);
  });

  it('never flags a product with no configured threshold (minStock 0, the DB default)', () => {
    expect(isLowStock(0, 0)).toBe(false);
  });
});
