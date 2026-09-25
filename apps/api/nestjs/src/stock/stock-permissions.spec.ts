import { describe, expect, it } from 'vitest';
import {
  ALL_STOCK_PERMISSIONS,
  STOCK_ACTIVE_LISTING_PERMISSION,
  STOCK_VALUE_PERMISSION,
  stockPermissionsOf,
} from './stock-permissions.js';

describe('stock-permissions', () => {
  it('les deux codes Stock à bascule client sont stock.view_value et stock.active_listing', () => {
    expect(STOCK_VALUE_PERMISSION).toBe('stock.view_value');
    expect(STOCK_ACTIVE_LISTING_PERMISSION).toBe('stock.active_listing');
    expect(ALL_STOCK_PERMISSIONS).toEqual(['stock.view_value', 'stock.active_listing']);
  });

  it('ne garde que les codes accordés parmi les permissions Stock connues', () => {
    expect(stockPermissionsOf(new Set(['stock.view_value', 'stock.manage']))).toEqual(['stock.view_value']);
    expect(stockPermissionsOf(new Set(['stock.active_listing']))).toEqual(['stock.active_listing']);
    expect(stockPermissionsOf(new Set(['stock.view']))).toEqual([]);
    expect(stockPermissionsOf(new Set())).toEqual([]);
  });
});
