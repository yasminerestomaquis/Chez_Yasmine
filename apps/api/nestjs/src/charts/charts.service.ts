import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import { computeFifoLots, type StockLotMovementType } from '../stock/stock-lots.js';
import type { ChartMetric } from './dto/chart-query.dto.js';

const WEEKDAY_LABELS = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
const MONTH_LABELS = [
  'Janvier',
  'Février',
  'Mars',
  'Avril',
  'Mai',
  'Juin',
  'Juillet',
  'Août',
  'Septembre',
  'Octobre',
  'Novembre',
  'Décembre',
];

interface SoldLine {
  createdAt: Date;
  revenue: number;
  cost: number;
  productId: string;
  productName: string;
  categoryId: string | null;
  categoryName: string;
}

interface WeekSeries {
  id: string | null;
  name: string;
  values: number[];
}

/** Monday (0) .. Sunday (6) of the ISO week, unlike `Date.getDay()` (Sunday = 0). */
function weekdayIndex(date: Date): number {
  return (date.getDay() + 6) % 7;
}

function mondayOf(date: Date): Date {
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() - weekdayIndex(d));
  return d;
}

function emptyWeek(): number[] {
  return [0, 0, 0, 0, 0, 0, 0];
}

function valueOf(metric: ChartMetric, line: Pick<SoldLine, 'revenue' | 'cost'>): number {
  return metric === 'revenue' ? line.revenue : line.revenue - line.cost;
}

/**
 * "Recettes" = chiffre d'affaires ligne à ligne (`quantité × prix de vente`),
 * jamais réduit par une remise (les remises ne sont enregistrées qu'au niveau
 * de la vente entière, pas par ligne) — even le graphique "total" (sans filtre)
 * additionne ces lignes plutôt que `Sale.total`, pour que la somme des
 * graphiques par catégorie/produit reconcilie toujours avec le total.
 * Conséquence assumée : ce total peut légèrement différer du "chiffre
 * d'affaires" du module Rapports (qui utilise `Sale.total`, net de remise).
 *
 * "Bénéfices" = marge brute (`revenue − quantité × prix d'achat actuel`),
 * jamais le bénéfice net après dépenses/pertes du module Rapports : les
 * dépenses et les pertes ne sont pas rattachées à un produit ou une
 * catégorie, donc il n'existe aucune façon correcte de les répartir dans un
 * graphique par catégorie/produit/jour.
 */
@Injectable()
export class ChartsService {
  constructor(private readonly prisma: PrismaService) {}

  private async soldLines(establishmentId: string, from: Date, to: Date): Promise<SoldLine[]> {
    const items = await this.prisma.saleItem.findMany({
      where: { sale: { establishmentId, voidedAt: null, createdAt: { gte: from, lte: to } } },
      select: {
        quantity: true,
        unitPrice: true,
        productId: true,
        name: true,
        sale: { select: { createdAt: true } },
        product: { select: { purchasePrice: true, categoryId: true, category: { select: { name: true } } } },
      },
    });
    return items.map((item) => {
      const quantity = item.quantity.toNumber();
      const unitPrice = item.unitPrice.toNumber();
      const purchasePrice = item.product.purchasePrice?.toNumber() ?? 0;
      return {
        createdAt: item.sale.createdAt,
        revenue: quantity * unitPrice,
        cost: quantity * purchasePrice,
        productId: item.productId,
        productName: item.name,
        categoryId: item.product.categoryId,
        categoryName: item.product.category?.name ?? 'Sans catégorie',
      };
    });
  }

  private weekRange(weekStart?: string): { from: Date; to: Date; monday: Date } {
    const monday = mondayOf(weekStart ? new Date(weekStart) : new Date());
    const to = new Date(monday);
    to.setDate(to.getDate() + 6);
    to.setHours(23, 59, 59, 999);
    return { from: monday, to, monday };
  }

  private buildWeekResponse(monday: Date, series: WeekSeries[]) {
    const weekEnd = new Date(monday);
    weekEnd.setDate(weekEnd.getDate() + 6);
    return {
      weekStart: monday.toISOString().slice(0, 10),
      weekEnd: weekEnd.toISOString().slice(0, 10),
      series: series.map((s) => ({
        id: s.id,
        name: s.name,
        points: WEEKDAY_LABELS.map((day, i) => ({ day, value: s.values[i] })),
      })),
    };
  }

  async weeklyTotal(establishmentId: string, metric: ChartMetric, weekStart?: string) {
    const { from, to, monday } = this.weekRange(weekStart);
    const lines = await this.soldLines(establishmentId, from, to);
    const values = emptyWeek();
    for (const line of lines) {
      values[weekdayIndex(line.createdAt)] += valueOf(metric, line);
    }
    return this.buildWeekResponse(monday, [{ id: null, name: 'Total', values }]);
  }

  async weeklyByCategory(establishmentId: string, metric: ChartMetric, weekStart?: string, categoryId?: string) {
    const { from, to, monday } = this.weekRange(weekStart);
    const lines = await this.soldLines(establishmentId, from, to);
    const filtered = categoryId ? lines.filter((l) => l.categoryId === categoryId) : lines;

    const byKey = new Map<string, WeekSeries>();
    for (const line of filtered) {
      const key = line.categoryId ?? '__none__';
      const entry = byKey.get(key) ?? { id: line.categoryId, name: line.categoryName, values: emptyWeek() };
      entry.values[weekdayIndex(line.createdAt)] += valueOf(metric, line);
      byKey.set(key, entry);
    }
    const series = [...byKey.values()].sort((a, b) => sumOf(b.values) - sumOf(a.values));
    return this.buildWeekResponse(monday, series);
  }

  async weeklyByProduct(establishmentId: string, metric: ChartMetric, weekStart?: string, productId?: string) {
    const { from, to, monday } = this.weekRange(weekStart);
    const lines = await this.soldLines(establishmentId, from, to);
    const filtered = productId ? lines.filter((l) => l.productId === productId) : lines;

    const byKey = new Map<string, WeekSeries>();
    for (const line of filtered) {
      const entry = byKey.get(line.productId) ?? { id: line.productId, name: line.productName, values: emptyWeek() };
      entry.values[weekdayIndex(line.createdAt)] += valueOf(metric, line);
      byKey.set(line.productId, entry);
    }
    const series = [...byKey.values()].sort((a, b) => sumOf(b.values) - sumOf(a.values));
    return this.buildWeekResponse(monday, series);
  }

  async monthly(establishmentId: string, metric: ChartMetric, year: number) {
    const from = new Date(year, 0, 1, 0, 0, 0, 0);
    const to = new Date(year, 11, 31, 23, 59, 59, 999);
    const lines = await this.soldLines(establishmentId, from, to);
    const values = new Array(12).fill(0) as number[];
    for (const line of lines) {
      values[line.createdAt.getMonth()] += valueOf(metric, line);
    }
    return { year, months: MONTH_LABELS.map((month, i) => ({ month, value: values[i] })) };
  }

  /**
   * Classement (§30 de la demande) : « recettes » classe par catégorie
   * (« type de produit »), « bénéfices » classe par produit individuel —
   * reprend exactement la distinction demandée plutôt qu'un seul groupement
   * générique. Plafonné à 10 lignes, comme `topProducts` dans le module
   * Rapports.
   */
  async top(establishmentId: string, metric: ChartMetric, from: Date, to: Date) {
    const lines = await this.soldLines(establishmentId, from, to);
    const groupBy: 'category' | 'product' = metric === 'revenue' ? 'category' : 'product';

    const agg = new Map<string, { id: string | null; name: string; value: number }>();
    for (const line of lines) {
      const key = groupBy === 'category' ? (line.categoryId ?? '__none__') : line.productId;
      const id = groupBy === 'category' ? line.categoryId : line.productId;
      const name = groupBy === 'category' ? line.categoryName : line.productName;
      const entry = agg.get(key) ?? { id, name, value: 0 };
      entry.value += valueOf(metric, line);
      agg.set(key, entry);
    }
    const items = [...agg.values()].sort((a, b) => b.value - a.value).slice(0, 10);
    return { from: from.toISOString(), to: to.toISOString(), groupBy, items };
  }

  /**
   * Sous-module "Stock" (maquette FIFO par lots — voir docs/api/charts.md) :
   * reconstruit les lots d'un produit à partir de son historique complet de
   * `StockMovement`, sans aucun schéma de lot dédié. Contrairement aux
   * autres graphiques de ce service, cette vue représente l'état COURANT du
   * stock (tout l'historique du produit, pas une période bornée par le
   * filtre Année de la page Graphiques) — un lot reçu il y a plusieurs
   * années peut rester actif aujourd'hui.
   */
  async stockLots(establishmentId: string, productId: string) {
    const product = await this.prisma.product.findFirst({
      where: { id: productId, establishmentId },
      select: { id: true, name: true },
    });
    if (!product) {
      throw new NotFoundException('Produit introuvable pour cet établissement');
    }

    const movements = await this.prisma.stockMovement.findMany({
      where: { productId },
      orderBy: { createdAt: 'asc' },
      select: { type: true, quantity: true, createdAt: true },
    });

    const lots = computeFifoLots(
      movements.map((m) => ({
        type: m.type as StockLotMovementType,
        quantity: m.quantity.toNumber(),
        createdAt: m.createdAt,
      })),
    );
    const activeLots = lots.filter((lot) => lot.status === 'actif');

    return {
      productId: product.id,
      productName: product.name,
      activeLots,
      historyLots: lots,
      totalActiveUnits: activeLots.reduce((sum, lot) => sum + lot.remainingQuantity, 0),
    };
  }
}

function sumOf(values: number[]): number {
  return values.reduce((sum, v) => sum + v, 0);
}
