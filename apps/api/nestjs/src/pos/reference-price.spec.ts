import { BadRequestException } from '@nestjs/common';
import { describe, expect, it } from 'vitest';
import { resolveReferencePriceLine } from './reference-price.js';

describe('resolveReferencePriceLine', () => {
  it('100 FCFA a 3000 FCFA/L donne 0,03 L (exemple utilisateur du 2026-09-24, arrondi a 2 decimales)', () => {
    const { quantity, unitPrice } = resolveReferencePriceLine(3000, 100, 'Gbêlê');
    expect(quantity).toBe(0.03);
    expect(quantity * unitPrice).toBeCloseTo(100, 6);
  });

  it('reproduit exactement le montant paye quel que soit larrondi de la quantite', () => {
    for (const amount of [50, 100, 250, 333, 1000, 3000, 4999]) {
      const { quantity, unitPrice } = resolveReferencePriceLine(3000, amount, 'Gbêlê');
      expect(quantity * unitPrice).toBeCloseTo(amount, 6);
    }
  });

  it('refuse un montant trop faible pour representer au moins 0,01 unite', () => {
    expect(() => resolveReferencePriceLine(3000, 10, 'Gbêlê')).toThrow(BadRequestException);
  });

  it('refuse un montant nul, negatif ou non fini', () => {
    expect(() => resolveReferencePriceLine(3000, 0, 'Gbêlê')).toThrow(BadRequestException);
    expect(() => resolveReferencePriceLine(3000, -50, 'Gbêlê')).toThrow(BadRequestException);
    expect(() => resolveReferencePriceLine(3000, Number.NaN, 'Gbêlê')).toThrow(BadRequestException);
  });

  it('accepte un prix de reference different (generalite, pas cable en dur a 3000)', () => {
    const { quantity } = resolveReferencePriceLine(4000, 2000, 'Gbêlê');
    expect(quantity).toBe(0.5);
  });
});
