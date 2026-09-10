import { describe, expect, it } from 'vitest';
import { computeFifoLots } from './stock-lots.js';

describe('computeFifoLots', () => {
  it('returns no lots for a product with no movements', () => {
    expect(computeFifoLots([])).toEqual([]);
  });

  it('reproduces the worked example from the reference mockup (Bières)', () => {
    // L001: 100 reçues → 100 consommées → 0 restante → épuisé
    // L002: 150 reçues → 70 consommées → 80 restantes → actif
    // L003: 120 reçues → 0 consommée → 120 restantes → actif
    const lots = computeFifoLots([
      { type: 'in', quantity: 100, createdAt: new Date('2025-08-20T08:00:00Z') },
      { type: 'in', quantity: 150, createdAt: new Date('2025-09-05T08:00:00Z') },
      { type: 'in', quantity: 120, createdAt: new Date('2025-09-10T08:00:00Z') },
      // 170 unités vendues au total : épuise L001 (100) puis entame L002 (70).
      { type: 'sale', quantity: 100, createdAt: new Date('2025-09-11T09:00:00Z') },
      { type: 'sale', quantity: 70, createdAt: new Date('2025-09-12T09:00:00Z') },
    ]);

    expect(lots).toEqual([
      {
        code: 'L001',
        referenceNumber: null,
        receivedAt: new Date('2025-08-20T08:00:00Z'),
        receivedQuantity: 100,
        consumedQuantity: 100,
        lossQuantity: 0,
        remainingQuantity: 0,
        status: 'epuise',
      },
      {
        code: 'L002',
        referenceNumber: null,
        receivedAt: new Date('2025-09-05T08:00:00Z'),
        receivedQuantity: 150,
        consumedQuantity: 70,
        lossQuantity: 0,
        remainingQuantity: 80,
        status: 'actif',
      },
      {
        code: 'L003',
        referenceNumber: null,
        receivedAt: new Date('2025-09-10T08:00:00Z'),
        receivedQuantity: 120,
        consumedQuantity: 0,
        lossQuantity: 0,
        remainingQuantity: 120,
        status: 'actif',
      },
    ]);

    const activeTotal = lots.filter((l) => l.status === 'actif').reduce((sum, l) => sum + l.remainingQuantity, 0);
    expect(activeTotal).toBe(200);
  });

  it('spills a single large consumption across multiple lots in FIFO order', () => {
    const lots = computeFifoLots([
      { type: 'in', quantity: 10, createdAt: new Date('2026-01-01T00:00:00Z') },
      { type: 'in', quantity: 10, createdAt: new Date('2026-01-02T00:00:00Z') },
      { type: 'out', quantity: 15, createdAt: new Date('2026-01-03T00:00:00Z') },
    ]);

    expect(lots[0]).toMatchObject({ remainingQuantity: 0, status: 'epuise' });
    expect(lots[1]).toMatchObject({ remainingQuantity: 5, status: 'actif' });
  });

  it('sorts out-of-order input movements chronologically before processing', () => {
    const lots = computeFifoLots([
      { type: 'out', quantity: 5, createdAt: new Date('2026-01-03T00:00:00Z') },
      { type: 'in', quantity: 10, createdAt: new Date('2026-01-01T00:00:00Z') },
    ]);

    expect(lots).toHaveLength(1);
    expect(lots[0].remainingQuantity).toBe(5);
  });

  it('creates a synthetic lot for a positive adjustment', () => {
    const lots = computeFifoLots([
      { type: 'in', quantity: 10, createdAt: new Date('2026-01-01T00:00:00Z') },
      { type: 'adjustment', quantity: 25, createdAt: new Date('2026-01-05T00:00:00Z') },
    ]);

    expect(lots).toHaveLength(2);
    expect(lots[0]).toMatchObject({ receivedQuantity: 10, remainingQuantity: 10 });
    expect(lots[1]).toMatchObject({
      receivedAt: new Date('2026-01-05T00:00:00Z'),
      receivedQuantity: 15,
      remainingQuantity: 15,
      status: 'actif',
    });
  });

  it('consumes lots in FIFO order for a negative adjustment, without creating a lot', () => {
    const lots = computeFifoLots([
      { type: 'in', quantity: 10, createdAt: new Date('2026-01-01T00:00:00Z') },
      { type: 'adjustment', quantity: 3, createdAt: new Date('2026-01-05T00:00:00Z') },
    ]);

    expect(lots).toHaveLength(1);
    expect(lots[0]).toMatchObject({ remainingQuantity: 3, consumedQuantity: 7, status: 'actif' });
  });

  it('leaves totals unchanged for a no-op adjustment (matches the running total exactly)', () => {
    const lots = computeFifoLots([
      { type: 'in', quantity: 10, createdAt: new Date('2026-01-01T00:00:00Z') },
      { type: 'adjustment', quantity: 10, createdAt: new Date('2026-01-05T00:00:00Z') },
    ]);

    expect(lots).toHaveLength(1);
    expect(lots[0]).toMatchObject({ remainingQuantity: 10, consumedQuantity: 0 });
  });

  it('numbers lots sequentially in chronological order regardless of movement type interleaving', () => {
    const lots = computeFifoLots([
      { type: 'in', quantity: 5, createdAt: new Date('2026-01-01T00:00:00Z') },
      { type: 'loss', quantity: 1, createdAt: new Date('2026-01-02T00:00:00Z') },
      { type: 'in', quantity: 5, createdAt: new Date('2026-01-03T00:00:00Z') },
    ]);

    expect(lots.map((l) => l.code)).toEqual(['L001', 'L002']);
  });

  it('parses the order/marché number from the movement reason', () => {
    const lots = computeFifoLots([
      { type: 'in', quantity: 10, createdAt: new Date('2026-01-01T00:00:00Z'), reason: 'Commande n°1' },
      { type: 'in', quantity: 5, createdAt: new Date('2026-01-05T00:00:00Z'), reason: 'Correction commande n°1' },
      { type: 'in', quantity: 8, createdAt: new Date('2026-01-10T00:00:00Z'), reason: 'Marché n°2' },
      { type: 'in', quantity: 3, createdAt: new Date('2026-01-15T00:00:00Z'), reason: 'Comptage manuel' },
      { type: 'in', quantity: 2, createdAt: new Date('2026-01-20T00:00:00Z') },
    ]);

    expect(lots.map((l) => l.referenceNumber)).toEqual([1, 1, 2, null, null]);
  });

  it('tracks loss quantity separately from sale/manual consumption on the same lot', () => {
    const lots = computeFifoLots([
      { type: 'in', quantity: 10, createdAt: new Date('2026-01-01T00:00:00Z') },
      { type: 'sale', quantity: 3, createdAt: new Date('2026-01-02T00:00:00Z') },
      { type: 'loss', quantity: 2, createdAt: new Date('2026-01-03T00:00:00Z') },
    ]);

    expect(lots).toHaveLength(1);
    expect(lots[0]).toMatchObject({ consumedQuantity: 5, lossQuantity: 2, remainingQuantity: 5 });
  });

  it('spreads loss across multiple lots in FIFO order, crediting only the units actually lost from each', () => {
    const lots = computeFifoLots([
      { type: 'in', quantity: 5, createdAt: new Date('2026-01-01T00:00:00Z') },
      { type: 'in', quantity: 5, createdAt: new Date('2026-01-02T00:00:00Z') },
      { type: 'loss', quantity: 8, createdAt: new Date('2026-01-03T00:00:00Z') },
    ]);

    expect(lots[0]).toMatchObject({ lossQuantity: 5, remainingQuantity: 0 });
    expect(lots[1]).toMatchObject({ lossQuantity: 3, remainingQuantity: 2 });
  });
});
