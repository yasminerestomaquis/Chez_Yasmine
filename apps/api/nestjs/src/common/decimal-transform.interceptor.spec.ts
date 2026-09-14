import { Decimal } from '@prisma/client';
import { of } from 'rxjs';
import { describe, expect, it } from 'vitest';
import { DecimalTransformInterceptor, transformDecimals } from './decimal-transform.interceptor.js';

describe('transformDecimals', () => {
  it('converts a bare Decimal to a plain number', () => {
    expect(transformDecimals(new Decimal('1500.5'))).toBe(1500.5);
  });

  it('converts Decimal fields nested in objects and arrays, recursively', () => {
    const input = {
      total: new Decimal('2500'),
      items: [
        { quantity: new Decimal('3'), unitPrice: new Decimal('500.5') },
        { quantity: new Decimal('1'), unitPrice: new Decimal('1000') },
      ],
      customer: { creditBalance: new Decimal('0') },
    };

    expect(transformDecimals(input)).toEqual({
      total: 2500,
      items: [
        { quantity: 3, unitPrice: 500.5 },
        { quantity: 1, unitPrice: 1000 },
      ],
      customer: { creditBalance: 0 },
    });
  });

  it('leaves Dates, strings, null and plain numbers untouched', () => {
    const date = new Date('2026-01-01T00:00:00.000Z');
    const input = { createdAt: date, label: 'Loyer', note: null, count: 4 };
    expect(transformDecimals(input)).toEqual({ createdAt: date, label: 'Loyer', note: null, count: 4 });
  });

  it('leaves a Buffer untouched instead of walking it byte-by-byte into a {"0":137,...} object (regression 2026-09-14: broke the Excel exports)', () => {
    const buffer = Buffer.from([0x50, 0x4b, 0x03, 0x04]); // signature ZIP, début réel d'un fichier .xlsx
    const result = transformDecimals(buffer);
    expect(Buffer.isBuffer(result)).toBe(true);
    expect(result).toBe(buffer);
    expect((result as Buffer).equals(buffer)).toBe(true);
  });
});

describe('DecimalTransformInterceptor', () => {
  it('applies transformDecimals to whatever the route handler returns', async () => {
    const interceptor = new DecimalTransformInterceptor();
    const result = await new Promise((resolve) => {
      interceptor
        .intercept({} as never, { handle: () => of({ amount: new Decimal('42') }) } as never)
        .subscribe((value) => resolve(value));
    });
    expect(result).toEqual({ amount: 42 });
  });
});
