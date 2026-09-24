import { Injectable } from '@nestjs/common';
import ExcelJS from 'exceljs';
import { PrismaService } from '../prisma/prisma.service.js';
import { effectiveUnitCost } from '../catalog/product-cost.util.js';
import { StockMovementsService } from '../stock/stock-movements.service.js';
import type { ReportQueryDto } from './dto/report-query.dto.js';
import { lossRevenueByGroup } from './loss-revenue.js';

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
   * groupe de catégories — **trois groupes depuis le 2026-09-24** : Boissons
   * sans Gbêlê (`hasCasePricing`, ex. Bières/Vins/Sucreries), Gbêlê
   * (`isBeverage` sans `hasCasePricing` — seule catégorie de ce groupe à ce
   * jour, prix d'achat connu, prix de vente saisi à chaque vente, décision
   * utilisateur du 2026-09-17) et Plats (`hasVariablePricing`, ex.
   * Poulets/Poissons/Plats africains — voir docs/api/catalog.md), plus le
   * croisement de chacun avec le mode de paiement. Auparavant Gbêlê comptait
   * dans "Boissons" (`hasCasePricing || isBeverage`) ; isolé sur demande
   * utilisateur pour distinguer "Recettes boissons sans Gbêlê"/"Recettes
   * Gbêlê" à l'Accueil.
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
   *
   * Les pertes de la période (valorisées au prix de vente) s'ajoutent, dans le
   * groupe de leur produit, à Mobile Money uniquement — donc aussi au total
   * des ventes — jamais à Espèces (demande utilisateur du 2026-09-20, voir
   * docs/api/reports.md).
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
            product: { select: { category: { select: { hasCasePricing: true, hasVariablePricing: true, isBeverage: true } } } },
          },
        },
      },
    });

    // Pertes de la période (date de la perte, éventuellement saisie), valorisées
    // au prix de vente : comptées côté Mobile Money uniquement, dans le groupe
    // Boissons/Plats de leur produit — jamais en Espèces (voir loss-revenue.ts).
    const losses = await this.prisma.loss.findMany({
      where: { establishmentId, createdAt: { gte: from, lte: to } },
      select: {
        quantity: true,
        sellAsUnit: true,
        product: {
          select: {
            salePrice: true,
            unitSalePrice: true,
            referenceSalePrice: true,
            category: { select: { hasCasePricing: true, hasVariablePricing: true, isBeverage: true } },
          },
        },
      },
    });
    const lossRevenue = lossRevenueByGroup(losses);

    let cashRevenue = 0;
    let mobileMoneyRevenue = 0;
    // Boissons sans Gbêlê (Bières/Vins/Sucreries, `hasCasePricing`) et Gbêlê
    // (`isBeverage` sans `hasCasePricing`) séparés le 2026-09-24 — auparavant
    // fusionnés sous "Boissons" (`hasCasePricing || isBeverage`).
    let boissonsSansGbeleRevenue = 0;
    let gbeleRevenue = 0;
    let platsRevenue = 0;
    let boissonsSansGbeleCash = 0;
    let boissonsSansGbeleMobileMoney = 0;
    let gbeleCash = 0;
    let gbeleMobileMoney = 0;
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

      let saleBoissonsSansGbele = 0;
      let saleGbele = 0;
      let salePlats = 0;
      for (const item of sale.items) {
        const revenue = item.quantity.toNumber() * item.unitPrice.toNumber();
        if (item.product.category?.hasCasePricing) saleBoissonsSansGbele += revenue;
        else if (item.product.category?.isBeverage) saleGbele += revenue;
        else if (item.product.category?.hasVariablePricing) salePlats += revenue;
      }
      boissonsSansGbeleRevenue += saleBoissonsSansGbele;
      gbeleRevenue += saleGbele;
      platsRevenue += salePlats;

      if (paidTotal > 0) {
        boissonsSansGbeleCash += saleBoissonsSansGbele * (cashAmount / paidTotal);
        boissonsSansGbeleMobileMoney += saleBoissonsSansGbele * (mobileMoneyAmount / paidTotal);
        gbeleCash += saleGbele * (cashAmount / paidTotal);
        gbeleMobileMoney += saleGbele * (mobileMoneyAmount / paidTotal);
        platsCash += salePlats * (cashAmount / paidTotal);
        platsMobileMoney += salePlats * (mobileMoneyAmount / paidTotal);
      }
    }

    const lossesRevenue = lossRevenue.boissonsSansGbele + lossRevenue.gbele + lossRevenue.plats;
    mobileMoneyRevenue += lossesRevenue;
    boissonsSansGbeleRevenue += lossRevenue.boissonsSansGbele;
    gbeleRevenue += lossRevenue.gbele;
    platsRevenue += lossRevenue.plats;
    boissonsSansGbeleMobileMoney += lossRevenue.boissonsSansGbele;
    gbeleMobileMoney += lossRevenue.gbele;
    platsMobileMoney += lossRevenue.plats;

    return {
      from,
      to,
      totalRevenue: cashRevenue + mobileMoneyRevenue,
      lossesRevenue,
      cashRevenue,
      mobileMoneyRevenue,
      boissonsSansGbeleRevenue,
      gbeleRevenue,
      platsRevenue,
      boissonsSansGbeleCash,
      boissonsSansGbeleMobileMoney,
      gbeleCash,
      gbeleMobileMoney,
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

  /**
   * Listing Excel des produits vendus des catégories "Boissons" — à prix par
   * casier (Bières/Vins/Sucreries — `hasCasePricing`) ou marquées `isBeverage`
   * (ex. Gbêlê, décision utilisateur du 2026-09-17 — voir docs/api/catalog.md)
   * pour un jour choisi par l'utilisateur, une ligne par `SaleItem` (pas
   * agrégé par produit : "Numéro de la commande" varie ligne à ligne, un même
   * produit pouvant appartenir à plusieurs ventes/commandes le même jour).
   */
  async beveragesSoldExcel(establishmentId: string, dateStr: string): Promise<{ buffer: Buffer; filename: string }> {
    const [year, month, day] = dateStr.split('-').map(Number);
    const from = new Date(year, month - 1, day, 0, 0, 0, 0);
    const to = new Date(year, month - 1, day, 23, 59, 59, 999);

    const items = await this.prisma.saleItem.findMany({
      where: {
        sale: { establishmentId, voidedAt: null, createdAt: { gte: from, lte: to } },
        product: { category: { OR: [{ hasCasePricing: true }, { isBeverage: true }] } },
      },
      include: { sale: { select: { orderNumber: true, createdAt: true } } },
      orderBy: { sale: { createdAt: 'asc' } },
    });

    const rows = items.map((item) => {
      const quantity = item.quantity.toNumber();
      const total = quantity * item.unitPrice.toNumber();
      return { name: item.name, orderNumber: item.sale.orderNumber, quantity, total };
    });
    const totalQuantity = rows.reduce((sum, r) => sum + r.quantity, 0);
    const totalAmount = rows.reduce((sum, r) => sum + r.total, 0);

    const workbook = new ExcelJS.Workbook();
    const sheet = workbook.addWorksheet('Boissons vendues');
    sheet.columns = [
      { header: 'Nom du produit', key: 'name', width: 30 },
      { header: 'Numéro de la commande', key: 'orderNumber', width: 22 },
      { header: 'Nombre de produits vendus', key: 'quantity', width: 24 },
      { header: 'Montant total produit vendu (FCFA)', key: 'total', width: 28 },
    ];
    sheet.getRow(1).font = { bold: true };
    for (const r of rows) {
      sheet.addRow({ name: r.name, orderNumber: r.orderNumber ?? '', quantity: r.quantity, total: r.total });
    }
    const totalRow = sheet.addRow({ name: 'TOTAL', orderNumber: '', quantity: totalQuantity, total: totalAmount });
    totalRow.font = { bold: true };

    const buffer = (await workbook.xlsx.writeBuffer()) as ExcelJS.Buffer;
    const pad = (n: number) => String(n).padStart(2, '0');
    const filename = `Boissons vendues ${pad(day)}-${pad(month)}-${year}.xlsx`;
    return { buffer: Buffer.from(buffer), filename };
  }

  /**
   * Même principe que `beveragesSoldExcel`, pour les catégories à prix
   * variable (Poulets/Poissons/Plats africains — `hasVariablePricing`, voir
   * docs/api/catalog.md) plutôt qu'à prix par casier. Colonne "Numéro de
   * marché" au lieu de "Numéro de la commande" — c'est `Sale.marketNumber`,
   * pas `orderNumber`, qui rattache ces catégories à une dépense « Marché »
   * (voir docs/api/pos.md, « N° de commande / N° de marché »).
   */
  async platsSoldExcel(establishmentId: string, dateStr: string): Promise<{ buffer: Buffer; filename: string }> {
    const [year, month, day] = dateStr.split('-').map(Number);
    const from = new Date(year, month - 1, day, 0, 0, 0, 0);
    const to = new Date(year, month - 1, day, 23, 59, 59, 999);

    const items = await this.prisma.saleItem.findMany({
      where: {
        sale: { establishmentId, voidedAt: null, createdAt: { gte: from, lte: to } },
        product: { category: { hasVariablePricing: true } },
      },
      include: { sale: { select: { marketNumber: true, createdAt: true } } },
      orderBy: { sale: { createdAt: 'asc' } },
    });

    const rows = items.map((item) => {
      const quantity = item.quantity.toNumber();
      const total = quantity * item.unitPrice.toNumber();
      return { name: item.name, marketNumber: item.sale.marketNumber, quantity, total };
    });
    const totalQuantity = rows.reduce((sum, r) => sum + r.quantity, 0);
    const totalAmount = rows.reduce((sum, r) => sum + r.total, 0);

    const workbook = new ExcelJS.Workbook();
    const sheet = workbook.addWorksheet('Plats vendus');
    sheet.columns = [
      { header: 'Nom du produit', key: 'name', width: 30 },
      { header: 'Numéro de marché', key: 'marketNumber', width: 22 },
      { header: 'Nombre de produits vendus', key: 'quantity', width: 24 },
      { header: 'Montant total produit vendu (FCFA)', key: 'total', width: 28 },
    ];
    sheet.getRow(1).font = { bold: true };
    for (const r of rows) {
      sheet.addRow({ name: r.name, marketNumber: r.marketNumber ?? '', quantity: r.quantity, total: r.total });
    }
    const totalRow = sheet.addRow({ name: 'TOTAL', marketNumber: '', quantity: totalQuantity, total: totalAmount });
    totalRow.font = { bold: true };

    const buffer = (await workbook.xlsx.writeBuffer()) as ExcelJS.Buffer;
    const pad = (n: number) => String(n).padStart(2, '0');
    const filename = `Plats vendus ${pad(day)}-${pad(month)}-${year}.xlsx`;
    return { buffer: Buffer.from(buffer), filename };
  }
}
