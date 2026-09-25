import { describe, expect, it } from 'vitest';
import {
  ALL_REPORTS_PERMISSIONS,
  REPORTS_BEVERAGES_SOLD_PERMISSION,
  REPORTS_EXPORT_PERMISSION,
  REPORTS_PLATS_SOLD_PERMISSION,
  reportsPermissionsOf,
} from './report-permissions.js';

describe('report-permissions', () => {
  it('liste les trois codes Rapports à bascule client (un par bouton de l\'AppBar)', () => {
    expect(REPORTS_BEVERAGES_SOLD_PERMISSION).toBe('reports.beverages_sold');
    expect(REPORTS_PLATS_SOLD_PERMISSION).toBe('reports.plats_sold');
    expect(REPORTS_EXPORT_PERMISSION).toBe('reports.export');
    expect(ALL_REPORTS_PERMISSIONS).toEqual(['reports.beverages_sold', 'reports.plats_sold', 'reports.export']);
  });

  it('ne garde que les codes accordés parmi les permissions Rapports connues', () => {
    expect(reportsPermissionsOf(new Set(['reports.beverages_sold', 'reports.view']))).toEqual(['reports.beverages_sold']);
    expect(reportsPermissionsOf(new Set(['reports.view']))).toEqual([]);
    expect(reportsPermissionsOf(new Set())).toEqual([]);
  });
});
