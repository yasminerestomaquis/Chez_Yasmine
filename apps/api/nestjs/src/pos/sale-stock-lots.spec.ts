import { ConflictException, ForbiddenException } from '@nestjs/common';
import { Decimal } from '@prisma/client';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import type { ActivityNotifierService } from '../notifications/activity-notifier.service.js';
import { saleStockUnits } from './sale-stock-units.js';
import type { SellGroupsService } from './sell-groups.service.js';
import { SalesService } from './sales.service.js';

/**
 * Décompte du stock des produits vendus par lot ET à l'unité (Despé 33,
 * Heineken 33 : « Lot (3) — 2 000 » / « Unité — 700 »), constaté faux en
 * production le 2026-10-15 : un lot de 3 ne retirait qu'une bouteille.
 */
const notifier = { notify: vi.fn() } as unknown as ActivityNotifierService;

function makePrisma() {
  const prisma: Record<string, any> = {
    product: { findMany: vi.fn(), update: vi.fn(), updateMany: vi.fn().mockResolvedValue({ count: 1 }) },
    stockMovement: { create: vi.fn() },
    sale: { create: vi.fn(), findFirst: vi.fn(), update: vi.fn() },
    saleItem: { update: vi.fn() },
    customer: { findFirst: vi.fn() },
    order: { findFirst: vi.fn() },
    $transaction: vi.fn(async (cb: (tx: unknown) => unknown) => cb(prisma)),
  };
  return prisma;
}

const CATEGORY = { hasCasePricing: true, hasVariablePricing: false, isBeverage: false };

const lotProduct = (stock = 30) => ({
  id: 'p1',
  establishmentId: 'est-1',
  name: 'Despé 33',
  unit: '3',
  salePrice: new Decimal(2000),
  unitSalePrice: new Decimal(700),
  referenceSalePrice: null,
  stockQuantity: new Decimal(stock),
  category: CATEGORY,
});

describe('saleStockUnits', () => {
  const product = { unit: '3', unitSalePrice: new Decimal(700) };

  it('un lot retire quantité × taille du lot, une unité retire la quantité', () => {
    expect(saleStockUnits(product, 2, false)).toBe(6);
    expect(saleStockUnits(product, 2, true)).toBe(2);
  });

  it('sans prix à l’unité, lot de taille 1 ou produit inconnu : la quantité telle quelle', () => {
    expect(saleStockUnits({ unit: '3', unitSalePrice: null }, 2, false)).toBe(2);
    expect(saleStockUnits({ unit: '1', unitSalePrice: new Decimal(600) }, 4, false)).toBe(4);
    expect(saleStockUnits({ unit: null, unitSalePrice: new Decimal(600) }, 4, false)).toBe(4);
    expect(saleStockUnits(undefined, 4, false)).toBe(4);
  });
});

describe('SalesService — décompte du stock par lot', () => {
  let prisma: ReturnType<typeof makePrisma>;
  let service: SalesService;

  beforeEach(() => {
    prisma = makePrisma();
    service = new SalesService(prisma as unknown as PrismaService, notifier);
    prisma.sale.create.mockResolvedValue({ id: 's1', items: [], payments: [] });
  });

  it('vente de 2 lots de 3 : 6 bouteilles retirées, mouvement `sale` de 6, ligne facturée 2 × 2 000', async () => {
    prisma.product.findMany.mockResolvedValue([lotProduct()]);

    await service.create('est-1', 'user-1', {
      items: [{ productId: 'p1', quantity: 2 }],
      payments: [{ method: 'cash', amount: 4000 }],
    } as any);

    expect(prisma.product.updateMany).toHaveBeenCalledWith({
      where: { id: 'p1', stockQuantity: { gte: 6 } },
      data: { stockQuantity: { decrement: 6 } },
    });
    expect(prisma.stockMovement.create.mock.calls[0][0].data).toMatchObject({ type: 'sale', quantity: 6 });
    const item = prisma.sale.create.mock.calls[0][0].data.items.create[0];
    expect(item).toMatchObject({ quantity: 2, unitPrice: 2000, sellAsUnit: false });
  });

  it('vente de 2 unités : 2 bouteilles retirées, prix à l’unité, `sellAsUnit` mémorisé', async () => {
    prisma.product.findMany.mockResolvedValue([lotProduct()]);

    await service.create('est-1', 'user-1', {
      items: [{ productId: 'p1', quantity: 2, sellAsUnit: true }],
      payments: [{ method: 'cash', amount: 1400 }],
    } as any);

    expect(prisma.product.updateMany.mock.calls[0][0].data).toEqual({ stockQuantity: { decrement: 2 } });
    expect(prisma.sale.create.mock.calls[0][0].data.items.create[0]).toMatchObject({
      quantity: 2,
      unitPrice: 700,
      sellAsUnit: true,
    });
  });

  it('refuse un lot que le stock en bouteilles ne couvre pas (5 lots = 15 bouteilles pour 10 en stock)', async () => {
    prisma.product.findMany.mockResolvedValue([lotProduct(10)]);

    await expect(
      service.create('est-1', 'user-1', {
        items: [{ productId: 'p1', quantity: 5 }],
        payments: [{ method: 'cash', amount: 10000 }],
      } as any),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(prisma.stockMovement.create).not.toHaveBeenCalled();
  });

  it('remboursement : restitue les bouteilles (2 lots = 6), pas les lots', async () => {
    prisma.sale.findFirst.mockResolvedValue({
      id: 's1',
      voidedAt: null,
      customerId: null,
      credits: [],
      items: [
        { productId: 'p1', quantity: new Decimal(2), sellAsUnit: false, product: { unit: '3', unitSalePrice: new Decimal(700) } },
        { productId: 'p2', quantity: new Decimal(1), sellAsUnit: true, product: { unit: '3', unitSalePrice: new Decimal(700) } },
      ],
    });
    prisma.sale.update.mockResolvedValue({});

    await service.refund('est-1', 'user-1', 's1');

    expect(prisma.product.update.mock.calls[0][0].data).toEqual({ stockQuantity: { increment: 6 } });
    expect(prisma.product.update.mock.calls[1][0].data).toEqual({ stockQuantity: { increment: 1 } });
    expect(prisma.stockMovement.create.mock.calls[0][0].data).toMatchObject({ type: 'in', quantity: 6 });
  });

  it('correction de quantité 2 → 3 lots : 3 bouteilles de plus retirées, total +2 000', async () => {
    prisma.sale.findFirst.mockResolvedValue({
      id: 's1',
      voidedAt: null,
      items: [
        {
          id: 'i1',
          productId: 'p1',
          quantity: new Decimal(2),
          unitPrice: new Decimal(2000),
          sellAsUnit: false,
          product: { unit: '3', unitSalePrice: new Decimal(700) },
        },
      ],
    });
    prisma.sale.update.mockResolvedValue({});

    await service.updateItemQuantity('est-1', 'user-1', 's1', 'i1', 3);

    expect(prisma.product.updateMany).toHaveBeenCalledWith({
      where: { id: 'p1', stockQuantity: { gte: 3 } },
      data: { stockQuantity: { decrement: 3 } },
    });
    expect(prisma.stockMovement.create.mock.calls[0][0].data).toMatchObject({ type: 'out', quantity: 3 });
    expect(prisma.sale.update.mock.calls[0][0].data).toEqual({
      subtotal: { increment: 2000 },
      total: { increment: 2000 },
    });
  });
});

describe('SalesService — saisie par groupe de recettes', () => {
  it('refuse la vente (403) quand le rôle n’a pas la permission du groupe, avant toute écriture', async () => {
    const prisma = makePrisma();
    prisma.product.findMany.mockResolvedValue([lotProduct()]);
    const sellGroups = {
      assertCanSell: vi.fn().mockRejectedValue(new ForbiddenException('Saisie non autorisée')),
    } as unknown as SellGroupsService;
    const service = new SalesService(prisma as unknown as PrismaService, notifier, sellGroups);

    await expect(
      service.create('est-1', 'user-9', {
        items: [{ productId: 'p1', quantity: 1 }],
        payments: [{ method: 'cash', amount: 2000 }],
      } as any),
    ).rejects.toBeInstanceOf(ForbiddenException);

    expect(sellGroups.assertCanSell).toHaveBeenCalledWith('user-9', 'est-1', [{ category: CATEGORY }]);
    expect(prisma.product.updateMany).not.toHaveBeenCalled();
    expect(prisma.sale.create).not.toHaveBeenCalled();
  });
});
