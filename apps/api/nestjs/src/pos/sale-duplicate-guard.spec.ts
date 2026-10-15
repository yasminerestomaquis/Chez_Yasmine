import { ConflictException } from '@nestjs/common';
import { Decimal } from '@prisma/client';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import type { ActivityNotifierService } from '../notifications/activity-notifier.service.js';
import { SalesService } from './sales.service.js';

/**
 * Double clic sur « Valider le paiement » (demande du 2026-10-15) : deux requêtes
 * portant deux identifiants différents enregistraient deux ventes identiques et
 * décomptaient le stock deux fois. Le serveur refuse une vente STRICTEMENT
 * identique reçue moins d'une minute après la première.
 */
const notifier = { notify: vi.fn() } as unknown as ActivityNotifierService;

function makePrisma() {
  const prisma: Record<string, any> = {
    product: { findMany: vi.fn(), update: vi.fn(), updateMany: vi.fn().mockResolvedValue({ count: 1 }) },
    stockMovement: { create: vi.fn() },
    sale: { create: vi.fn(), findFirst: vi.fn(), findMany: vi.fn(), update: vi.fn() },
    customer: { findFirst: vi.fn() },
    order: { findFirst: vi.fn() },
    $transaction: vi.fn(async (cb: (tx: unknown) => unknown) => cb(prisma)),
  };
  return prisma;
}

const castel = {
  id: 'p1',
  establishmentId: 'est-1',
  name: 'Castel',
  unit: '1',
  salePrice: new Decimal(600),
  unitSalePrice: null,
  referenceSalePrice: null,
  stockQuantity: new Decimal(20),
  category: null,
};

/** Vente déjà enregistrée : 2 Castel à 600, payés 1 200 en espèces, il y a 3 secondes. */
const recentSale = (over: Record<string, unknown> = {}) => ({
  id: 'sale-1',
  source: 'pos',
  tableId: null,
  orderId: null,
  customerId: null,
  orderNumber: null,
  marketNumber: null,
  total: new Decimal(1200),
  discount: new Decimal(0),
  createdAt: new Date(Date.now() - 3000),
  items: [{ productId: 'p1', quantity: new Decimal(2), unitPrice: new Decimal(600), sellAsUnit: false }],
  payments: [{ method: 'cash', amount: new Decimal(1200) }],
  ...over,
});

const dto = (over: Record<string, unknown> = {}) =>
  ({
    id: 'nouvel-uuid',
    items: [{ productId: 'p1', quantity: 2 }],
    payments: [{ method: 'cash', amount: 1200 }],
    ...over,
  }) as any;

describe('SalesService — refus des ventes identiques rapprochées', () => {
  let prisma: ReturnType<typeof makePrisma>;
  let service: SalesService;

  beforeEach(() => {
    prisma = makePrisma();
    service = new SalesService(prisma as unknown as PrismaService, notifier);
    prisma.product.findMany.mockResolvedValue([castel]);
    prisma.sale.create.mockResolvedValue({ id: 'new', items: [], payments: [] });
    prisma.sale.findMany.mockResolvedValue([]);
  });

  it('refuse (409) la même vente reçue 3 secondes après, sans toucher au stock', async () => {
    prisma.sale.findMany.mockResolvedValue([recentSale()]);

    await expect(service.create('est-1', 'user-1', dto())).rejects.toBeInstanceOf(ConflictException);
    await expect(service.create('est-1', 'user-1', dto())).rejects.toThrow(/déjà été enregistrée il y a 3 s/);

    expect(prisma.product.updateMany).not.toHaveBeenCalled();
    expect(prisma.stockMovement.create).not.toHaveBeenCalled();
    expect(prisma.sale.create).not.toHaveBeenCalled();
  });

  it('ne compare qu’aux ventes du même utilisateur, non annulées, de la dernière minute', async () => {
    await service.create('est-1', 'user-1', dto());

    const where = prisma.sale.findMany.mock.calls[0][0].where;
    expect(where).toMatchObject({ establishmentId: 'est-1', createdBy: 'user-1', voidedAt: null });
    expect(Date.now() - where.createdAt.gte.getTime()).toBeLessThan(61_000);
    expect(prisma.sale.create).toHaveBeenCalled();
  });

  it.each([
    ['une quantité différente', { items: [{ productId: 'p1', quantity: 3 }], payments: [{ method: 'cash', amount: 1800 }] }],
    ['un autre mode de paiement', { payments: [{ method: 'mobile_money', amount: 1200 }] }],
    ['un autre produit', { items: [{ productId: 'p2', quantity: 2 }] }],
    ['un N° de commande', { orderNumber: 7 }],
    ['une remise', { discount: { type: 'amount', value: 100 }, payments: [{ method: 'cash', amount: 1100 }] }],
  ])('n’est pas un doublon : %s', async (_label, change) => {
    prisma.sale.findMany.mockResolvedValue([recentSale()]);
    const catalog = [castel, { ...castel, id: 'p2', name: 'Heineken' }];
    prisma.product.findMany.mockImplementation(async ({ where }: any) => catalog.filter((p) => where.id.in.includes(p.id)));

    await expect(service.create('est-1', 'user-1', dto(change))).resolves.toBeDefined();
    expect(prisma.sale.create).toHaveBeenCalled();
  });

  it('une vente à l’unité n’est pas un doublon d’une vente au lot du même produit', async () => {
    const lot = { ...castel, unit: '3', salePrice: new Decimal(2000), unitSalePrice: new Decimal(700) };
    prisma.product.findMany.mockResolvedValue([lot]);
    prisma.sale.findMany.mockResolvedValue([
      recentSale({
        total: new Decimal(1400),
        items: [{ productId: 'p1', quantity: new Decimal(2), unitPrice: new Decimal(700), sellAsUnit: true }],
        payments: [{ method: 'cash', amount: new Decimal(1400) }],
      }),
    ]);

    // Même quantité, mais au lot (2 × 2 000) : lignes et total différents.
    await expect(
      service.create('est-1', 'user-1', dto({ payments: [{ method: 'cash', amount: 4000 }] })),
    ).resolves.toBeDefined();
  });

  it('une vente antidatée n’est comparée qu’aux ventes de cette même date', async () => {
    const chosen = '2026-10-10T10:00:00.000Z';

    await service.create('est-1', 'user-1', dto({ createdAt: chosen }));

    expect(prisma.sale.findMany.mock.calls[0][0].where.createdAt).toEqual(new Date(chosen));
  });

  it('le rejeu de la file hors ligne ignore la garde (deux ventes identiques mises en file sont légitimes)', async () => {
    prisma.sale.findMany.mockResolvedValue([recentSale()]);

    await expect(service.create('est-1', 'user-1', dto(), { skipDuplicateGuard: true })).resolves.toBeDefined();
    expect(prisma.sale.findMany).not.toHaveBeenCalled();
    expect(prisma.sale.create).toHaveBeenCalled();
  });
});
