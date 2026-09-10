import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import { effectiveUnitCost } from '../catalog/product-cost.util.js';
import { StockMovementsService } from '../stock/stock-movements.service.js';
import type { ReportQueryDto } from './dto/report-query.dto.js';

export interface ReportRange {
  from: Date;
  to: Date;
}

@Injectable()
export class ReportsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly stockMovements: StockMovementsService,
  ) {}

  /** An explicit from/to wins; otherwise `period` (default 'day') is resolved against now. */
  resolveRange(query: ReportQueryDto): ReportRange {
    if (query.from || query.to) {
      return {
        from: query.from ? new Date(query.from) : new Date(0),
        to: query.to ? new Date(query.to) : new Date(),
      };
    }
    const to = new Date();
    const from = new Date(to);
    switch (query.period ?? 'day') {
      case 'day':
        from.setHours(0, 0, 0, 0);
        break;
      case 'week':
        from.setDate(from.getDate() - 7);
        break;
      case 'month':
        from.setMonth(from.getMonth() - 1);
        break;
      case 'year':
        from.setFullYear(from.getFullYear() - 1);
        break;
    }
    return { from, to };
  }

  /**
   * Every figure below is computed from data already in the schema — no new
   * tables. Two simplifications, both documented in docs/api/reports.md:
   * `cogs` uses each product's *current* purchasePrice (SaleItem doesn't
   * snapshot a historical cost), and `receivables` is a present-moment
   * balance snapshot, not scoped to the requested period like every other
   * figure here.
   */
  async summary(establishmentId: string, query: ReportQueryDto) {
    const { from, to } = this.resolveRange(query);

    const [sales, expenseAgg, losses, receivablesAgg, lowStockAlerts] = await Promise.all([
      this.prisma.sale.findMany({
        where: { establishmentId, voidedAt: null, createdAt: { gte: from, lte: to } },
        include: { items: true },
      }),
      this.prisma.expense.aggregate({
        _sum: { amount: true },
        where: { establishmentId, expenseDate: { gte: from, lte: to } },
      }),
      this.prisma.loss.findMany({
        where: { establishmentId, createdAt: { gte: from, lte: to } },
        include: {
          product: {
            select: {
              purchasePrice: true,
              bottlesPerCase: true,
              purchasePricePerCase: true,
              category: { select: { hasCasePricing: true } },
            },
          },
        },
      }),
      this.prisma.customer.aggregate({ _sum: { creditBalance: true }, where: { establishmentId } }),
      this.stockMovements.listLowStockAlerts(establishmentId),
    ]);

    const revenue = sales.reduce((sum, s) => sum + s.total.toNumber(), 0);
    const discountTotal = sales.reduce((sum, s) => sum + s.discount.toNumber(), 0);
    const salesCount = sales.length;

    const productIds = [...new Set(sales.flatMap((s) => s.items.map((i) => i.productId)))];
    const products = productIds.length
      ? await this.prisma.product.findMany({
          where: { id: { in: productIds } },
          select: {
            id: true,
            purchasePrice: true,
            bottlesPerCase: true,
            purchasePricePerCase: true,
            category: { select: { hasCasePricing: true } },
          },
        })
      : [];
    const purchasePriceById = new Map(products.map((p) => [p.id, effectiveUnitCost(p)]));

    let cogs = 0;
    const productAgg = new Map<string, { name: string; quantity: number; revenue: number; cost: number }>();
    for (const sale of sales) {
      for (const item of sale.items) {
        const quantity = item.quantity.toNumber();
        const unitPrice = item.unitPrice.toNumber();
        const lineCost = quantity * (purchasePriceById.get(item.productId) ?? 0);
        cogs += lineCost;
        const existing = productAgg.get(item.productId) ?? { name: item.name, quantity: 0, revenue: 0, cost: 0 };
        existing.quantity += quantity;
        existing.revenue += quantity * unitPrice;
        existing.cost += lineCost;
        productAgg.set(item.productId, existing);
      }
    }
    const withProfit = [...productAgg.entries()].map(([productId, v]) => ({ productId, ...v, profit: v.revenue - v.cost }));
    const topProducts = [...withProfit].sort((a, b) => b.quantity - a.quantity).slice(0, 5);
    // Bénéfice par produit (§ voir docs/api/reports.md) : même limitation que `cogs` —
    // coût d'achat *actuel*, pas figé au moment de chaque vente historique.
    const productProfitability = [...withProfit].sort((a, b) => b.profit - a.profit);

    const serverAgg = new Map<string, { total: number; salesCount: number }>();
    for (const sale of sales) {
      if (!sale.createdBy) continue;
      const existing = serverAgg.get(sale.createdBy) ?? { total: 0, salesCount: 0 };
      existing.total += sale.total.toNumber();
      existing.salesCount += 1;
      serverAgg.set(sale.createdBy, existing);
    }
    const serverIds = [...serverAgg.keys()];
    const servers = serverIds.length
      ? await this.prisma.userProfile.findMany({ where: { id: { in: serverIds } }, select: { id: true, fullName: true } })
      : [];
    const serverNameById = new Map(servers.map((u) => [u.id, u.fullName ?? u.id]));
    const serverPerformance = [...serverAgg.entries()]
      .map(([userId, v]) => ({ userId, name: serverNameById.get(userId) ?? userId, ...v }))
      .sort((a, b) => b.total - a.total);

    const lossesTotal = losses.reduce((sum, l) => sum + l.quantity.toNumber() * effectiveUnitCost(l.product), 0);
    const expensesTotal = expenseAgg._sum.amount?.toNumber() ?? 0;
    const grossMargin = revenue - cogs;
    const netProfit = grossMargin - expensesTotal - lossesTotal;

    return {
      from,
      to,
      revenue,
      salesCount,
      discountTotal,
      cogs,
      grossMargin,
      expenses: expensesTotal,
      losses: lossesTotal,
      netProfit,
      receivables: receivablesAgg._sum.creditBalance?.toNumber() ?? 0,
      lowStockCount: lowStockAlerts.length,
      topProducts,
      productProfitability,
      serverPerformance,
    };
  }

  /**
   * Ventilation utilisée par le tableau de bord Accueil : chiffre d'affaires
   * du jour réparti par mode de paiement (Espèces/Mobile Money) et par
   * groupe de catégories (Boissons = `hasCasePricing`, ex. Bières/Vins/
   * Sucreries ; Plats = `hasVariablePricing`, ex. Poulets/Poissons/Plats
   * africains — voir docs/api/catalog.md), plus le croisement des deux.
   *
   * Le CA par groupe de catégories est calculé ligne à ligne
   * (`SaleItem.quantity × SaleItem.unitPrice`), **jamais réduit par une
   * remise** — même convention que `ChartsService` (docs/api/charts.md) —
   * alors que Espèces/Mobile Money reflètent l'argent réellement encaissé
   * (`Payment.amount`, net de remise). Les deux ne se recoupent donc pas
   * exactement sur une vente avec remise, choix délibéré de cohérence avec
   * Graphiques plutôt qu'un alignement strict entre les deux totaux.
   *
   * Le croisement catégorie × mode de paiement répartit le CA de chaque
   * groupe au prorata de la part Espèces/Mobile Money de chaque vente —
   * même principe de répartition proportionnelle que l'allocation du coût
   * « Marché » dans ChartsService. Les paiements Carte/Crédit existants
   * (anciennes ventes, module Clients) ne comptent dans aucun des deux
   * totaux demandés (Espèces/Mobile Money uniquement).
   */
  async paymentCategoryBreakdown(establishmentId: string, query: ReportQueryDto) {
    const { from, to } = this.resolveRange(query);

    const sales = await this.prisma.sale.findMany({
      where: { establishmentId, voidedAt: null, createdAt: { gte: from, lte: to } },
      select: {
        payments: { select: { method: true, amount: true } },
        items: {
          select: {
            quantity: true,
            unitPrice: true,
            product: { select: { category: { select: { hasCasePricing: true, hasVariablePricing: true } } } },
          },
        },
      },
    });

    let cashRevenue = 0;
    let mobileMoneyRevenue = 0;
    let boissonsRevenue = 0;
    let platsRevenue = 0;
    let boissonsCash = 0;
    let boissonsMobileMoney = 0;
    let platsCash = 0;
    let platsMobileMoney = 0;

    for (const sale of sales) {
      const cashAmount = sale.payments.filter((p) => p.method === 'cash').reduce((sum, p) => sum + p.amount.toNumber(), 0);
      const mobileMoneyAmount = sale.payments
        .filter((p) => p.method === 'mobile_money')
        .reduce((sum, p) => sum + p.amount.toNumber(), 0);
      const paidTotal = sale.payments.reduce((sum, p) => sum + p.amount.toNumber(), 0);
      cashRevenue += cashAmount;
      mobileMoneyRevenue += mobileMoneyAmount;

      let saleBoissons = 0;
      let salePlats = 0;
      for (const item of sale.items) {
        const revenue = item.quantity.toNumber() * item.unitPrice.toNumber();
        if (item.product.category?.hasCasePricing) saleBoissons += revenue;
        else if (item.product.category?.hasVariablePricing) salePlats += revenue;
      }
      boissonsRevenue += saleBoissons;
      platsRevenue += salePlats;

      if (paidTotal > 0) {
        boissonsCash += saleBoissons * (cashAmount / paidTotal);
        boissonsMobileMoney += saleBoissons * (mobileMoneyAmount / paidTotal);
        platsCash += salePlats * (cashAmount / paidTotal);
        platsMobileMoney += salePlats * (mobileMoneyAmount / paidTotal);
      }
    }

    return {
      from,
      to,
      totalRevenue: cashRevenue + mobileMoneyRevenue,
      cashRevenue,
      mobileMoneyRevenue,
      boissonsRevenue,
      platsRevenue,
      boissonsCash,
      boissonsMobileMoney,
      platsCash,
      platsMobileMoney,
    };
  }

  /**
   * CSV export only — PDF/Excel from the master prompt's §34 are deferred
   * (see docs/api/reports.md): both need a real rendering dependency, and
   * this app has no round-trip-verified deployment yet to justify adding
   * one untested. CSV needs nothing beyond string formatting.
   */
  async summaryCsv(establishmentId: string, query: ReportQueryDto): Promise<string> {
    const s = await this.summary(establishmentId, query);
    const rows: [string, string | number][] = [
      ['Période début', s.from.toISOString()],
      ['Période fin', s.to.toISOString()],
      ["Chiffre d'affaires", s.revenue],
      ['Nombre de ventes', s.salesCount],
      ['Remises', s.discountTotal],
      ['Coût des marchandises vendues', s.cogs],
      ['Marge brute', s.grossMargin],
      ['Dépenses', s.expenses],
      ['Pertes', s.losses],
      ['Bénéfice net (estimé)', s.netProfit],
      ['Créances clients', s.receivables],
      ['Produits en alerte de stock', s.lowStockCount],
      ...s.productProfitability.map(
        (p): [string, number] => [`Bénéfice — ${p.name}`, p.profit],
      ),
    ];
    return ['"Indicateur","Valeur"', ...rows.map(([label, value]) => `"${label}",${value}`)].join('\n');
  }
}
