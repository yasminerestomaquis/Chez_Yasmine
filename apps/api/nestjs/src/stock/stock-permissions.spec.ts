import { describe, expect, it } from 'vitest';
import { ALL_STOCK_PERMISSIONS, STOCK_VALUE_PERMISSION, stockPermissionsOf } from './stock-permissions.js';

describe('stock-permissions', () => {
  it('le seul code Stock à bascule client est stock.view_value', () => {
    expect(STOCK_VALUE_PERMISSION).toBe('stock.view_value');
    expect(ALL_STOCK_PERMISSIONS).toEqual(['stock.view_value']);
  });

  it('ne garde que les codes accordés parmi les permissions Stock connues', () => {
    expect(stockPermissionsOf(new Set(['stock.view_value', 'stock.manage']))).toEqual(['stock.view_value']);
    expect(stockPermissionsOf(new Set(['stock.view']))).toEqual([]);
    expect(stockPermissionsOf(new Set())).toEqual([]);
  });
});
