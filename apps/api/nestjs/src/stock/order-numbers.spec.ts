import { BadRequestException } from '@nestjs/common';
import { Decimal } from '@prisma/client';
import { describe, expect, it, vi } from 'vitest';
import { computeFifoLots } from './stock-lots.js';
import { orderNumberChoices, reasonWithOrder, resolveOrderNumber } from './order-numbers.js';

const caseProduct = { id: 'p1', category: { hasCasePricing: true } };

describe('resolveOrderNumber', () => {
  it('ne demande rien pour un produit hors prix par casier', async () => {
    const prisma = { purchase: { findFirst: vi.fn() } };
    expect(await resolveOrderNumber(prisma as never, 'est', { id: 'p2', category: { hasCasePricing: false } }, undefined)).toBeUndefined();
    expect(prisma.purchase.findFirst).not.toHaveBeenCalled();
  });

  it('refuse un N° de commande absent pour un produit a casier', async () => {
    const prisma = { purchase: { findFirst: vi.fn() } };
    await expect(resolveOrderNumber(prisma as never, 'est', caseProduct, undefined)).rejects.toBeInstanceOf(BadRequestException);
  });

  it('refuse une commande qui ne contient pas le produit', async () => {
    const prisma = { purchase: { findFirst: vi.fn().mockResolvedValue(null) } };
    await expect(resolveOrderNumber(prisma as never, 'est', caseProduct, 4)).rejects.toBeInstanceOf(BadRequestException);
  });

  it('accepte une commande existante', async () => {
    const prisma = { purchase: { findFirst: vi.fn().mockResolvedValue({ id: 'x' }) } };
    expect(await resolveOrderNumber(prisma as never, 'est', caseProduct, 1)).toBe(1);
  });
});

describe('reasonWithOrder', () => {
  it('prefixe le motif avec la commande', () => {
    expect(reasonWithOrder(2, 'Casse')).toBe('Commande n°2 — Casse');
    expect(reasonWithOrder(2, undefined)).toBe('Commande n°2');
    expect(reasonWithOrder(undefined, 'Casse')).toBe('Casse');
  });
});

describe('orderNumberChoices', () => {
  const makePrisma = (movements: unknown[], purchases: number[]) => ({
    product: { findFirst: vi.fn().mockResolvedValue({ category: { hasCasePricing: true } }) },
    purchase: { findMany: vi.fn().mockResolvedValue(purchases.map((orderNumber) => ({ orderNumber }))) },
    stockMovement: { findMany: vi.fn().mockResolvedValue(movements) },
  });
  const inMove = (q: number, day: number, reason: string) => ({ type: 'in', quantity: new Decimal(q), createdAt: new Date(`2026-09-${day}T08:00:00Z`), reason });

  it('propose par defaut la commande du dernier lot actif', async () => {
    const prisma = makePrisma([inMove(10, 10, 'Commande n°1'), inMove(10, 12, 'Commande n°2')], [1, 2]);
    const result = await orderNumberChoices(prisma as never, 'est', 'p1');
    expect(result).toEqual({ required: true, options: [2, 1], defaultOrderNumber: 2 });
  });

  it('retombe sur le lot le plus recent quand tous sont epuises', async () => {
    const prisma = makePrisma([inMove(5, 10, 'Commande n°1'), { type: 'sale', quantity: new Decimal(5), createdAt: new Date('2026-09-11T08:00:00Z'), reason: null }], [1, 3]);
    const result = await orderNumberChoices(prisma as never, 'est', 'p1');
    expect(result.defaultOrderNumber).toBe(1);
  });

  it('nest pas requis hors prix par casier', async () => {
    const prisma = makePrisma([], []);
    prisma.product.findFirst.mockResolvedValue({ category: { hasCasePricing: false } });
    expect(await orderNumberChoices(prisma as never, 'est', 'p1')).toEqual({ required: false, options: [], defaultOrderNumber: null });
  });
});

describe('computeFifoLots - mouvement rattache a une commande', () => {
  it('une perte de la commande 2 consomme dabord le lot de la commande 2', () => {
    const lots = computeFifoLots([
      { type: 'in', quantity: 10, createdAt: new Date('2026-09-10'), reason: 'Commande n°1' },
      { type: 'in', quantity: 10, createdAt: new Date('2026-09-11'), reason: 'Commande n°2' },
      { type: 'loss', quantity: 3, createdAt: new Date('2026-09-12'), reason: 'Commande n°2 — Casse' },
    ]);
    expect(lots.map((l) => [l.referenceNumber, l.remainingQuantity, l.lossQuantity])).toEqual([
      [1, 10, 0],
      [2, 7, 3],
    ]);
  });
});
