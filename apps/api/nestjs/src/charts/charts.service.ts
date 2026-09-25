import { Injectable, NotFoundException } from '@nestjs/common';
import PDFDocument from 'pdfkit';
import { effectiveUnitCost } from '../catalog/product-cost.util.js';
import { drawPdfTable, formatFcfa } from '../common/pdf-table.util.js';
import { PrismaService } from '../prisma/prisma.service.js';
import { computeFifoLots, type StockLot, type StockLotMovementType } from '../stock/stock-lots.js';
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
  /** Usage interne à soldLines()/allocateMarcheCost() uniquement — jamais exposé dans une réponse. */
  isVariablePricing: boolean;
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

/** Clé "jour civil" (mêmes composantes locales que weekdayIndex/mondayOf ci-dessus), pour regrouper ventes et dépenses "Marché" du même jour. */
function dayKey(date: Date): string {
  return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
}

function valueOf(metric: ChartMetric, line: Pick<SoldLine, 'revenue' | 'cost'>): number {
  return metric === 'revenue' ? line.revenue : line.revenue - line.cost;
}

const MS_PER_DAY = 24 * 60 * 60 * 1000;

/**
 * Cycle de facturation habituel (en jours) des natures de dépenses dont le
 * rythme réel dépasse la granularité "semaine"/"mois" des graphiques
 * "Bénéfices" — décision utilisateur du 2026-09-13 : le bénéfice total
 * (hebdomadaire/mensuel) doit refléter une PART de ces charges plutôt que
 * de les ignorer (comme avant) ou de les compter en entier le seul jour où
 * elles sont payées (ce qui créerait un creux artificiel ce jour-là et un
 * bénéfice surestimé le reste du temps). Ex. Loyer payé une fois par mois :
 * une semaine de 7 jours n'en supporte que 7/30 ≈ le quart. Absente d'ici =
 * pas de lissage, comptée intégralement à sa date réelle (Salaires — déjà
 * hebdomadaire par construction, voir PayrollService —, Entretien,
 * Bouteilles de gaz, Charbon, "Autre" : aucun rythme fixe connu). "Marché"
 * n'apparaît jamais ici : déjà imputée ligne à ligne par
 * `allocateMarcheCost`, qui resterait sinon comptée deux fois.
 */
const AMORTIZED_CATEGORY_CYCLE_DAYS: Record<string, number> = {
  Loyer: 30,
  Cie: 30,
  Eau: 30,
  Patentes: 365,
};

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

  /**
   * Poulets, Poissons, Plats africains (`Category.hasVariablePricing`) n'ont
   * aucun prix d'achat catalogue (`effectiveUnitCost` y retombe toujours sur
   * `purchasePrice`, resté nul par design — voir docs/api/catalog.md), donc
   * `cost` vaut 0 pour ces lignes ici ; `allocateMarcheCost` le corrige juste
   * après en répartissant la dépense "Marché" du jour au prorata du chiffre
   * d'affaires (voir docs/api/reports.md pour le raisonnement complet).
   */
  private async soldLines(establishmentId: string, from: Date, to: Date): Promise<SoldLine[]> {
    const items = await this.prisma.saleItem.findMany({
      where: { sale: { establishmentId, voidedAt: null, createdAt: { gte: from, lte: to } } },
      select: {
        quantity: true,
        unitPrice: true,
        productId: true,
        name: true,
        sale: { select: { createdAt: true } },
        product: {
          select: {
            purchasePrice: true,
            bottlesPerCase: true,
            purchasePricePerCase: true,
            categoryId: true,
            category: { select: { name: true, hasCasePricing: true, hasVariablePricing: true } },
          },
        },
      },
    });
    const lines = items.map((item) => {
      const quantity = item.quantity.toNumber();
      const unitPrice = item.unitPrice.toNumber();
      return {
        createdAt: item.sale.createdAt,
        revenue: quantity * unitPrice,
        cost: quantity * effectiveUnitCost(item.product),
        productId: item.productId,
        productName: item.name,
        categoryId: item.product.categoryId,
        categoryName: item.product.category?.name ?? 'Sans catégorie',
        isVariablePricing: item.product.category?.hasVariablePricing ?? false,
      };
    });
    await this.allocateMarcheCost(establishmentId, from, to, lines);
    return lines;
  }

  /**
   * Répartit chaque jour la dépense "Marché" entre les lignes de vente des
   * catégories à prix variable (Poulets, Poissons, Plats africains), au
   * prorata du chiffre d'affaires de CE jour parmi ces catégories — décision
   * explicite de l'utilisateur (2026-09-10), après abandon d'un suivi du
   * coût produit par produit (le prix d'achat varie trop d'un jour à l'autre
   * pour qu'un "dernier prix connu" reste fiable rétroactivement). Aucune
   * dépense "Marché" ce jour-là (ou aucune vente de ces catégories) : coût
   * nul pour ces lignes ce jour, comme aujourd'hui.
   */
  private async allocateMarcheCost(establishmentId: string, from: Date, to: Date, lines: SoldLine[]): Promise<void> {
    const variableLines = lines.filter((l) => l.isVariablePricing);
    if (variableLines.length === 0) return;

    const marcheExpenses = await this.prisma.expense.findMany({
      where: { establishmentId, category: 'Marché', expenseDate: { gte: from, lte: to } },
      select: { amount: true, expenseDate: true },
    });
    if (marcheExpenses.length === 0) return;

    const marcheByDay = new Map<string, number>();
    for (const e of marcheExpenses) {
      const key = dayKey(e.expenseDate);
      marcheByDay.set(key, (marcheByDay.get(key) ?? 0) + e.amount.toNumber());
    }

    const revenueByDay = new Map<string, number>();
    for (const line of variableLines) {
      const key = dayKey(line.createdAt);
      revenueByDay.set(key, (revenueByDay.get(key) ?? 0) + line.revenue);
    }

    for (const line of variableLines) {
      const key = dayKey(line.createdAt);
      const marcheForDay = marcheByDay.get(key) ?? 0;
      const dayRevenue = revenueByDay.get(key) ?? 0;
      line.cost = dayRevenue > 0 ? marcheForDay * (line.revenue / dayRevenue) : 0;
    }
  }

  /**
   * Part de chaque dépense à cycle long (voir `AMORTIZED_CATEGORY_CYCLE_DAYS`)
   * qui recouvre effectivement `[from, to]`, au prorata du nombre de jours de
   * recouvrement — une dépense datée avant `from` peut donc contribuer (ex.
   * un loyer payé le 1er du mois compte pour toutes les semaines de ce
   * mois). La fenêtre de recherche remonte jusqu'à `maxCycleDays` avant
   * `from` pour ne manquer aucune dépense dont le cycle empièterait sur la
   * période demandée.
   */
  private async amortizedOverheadTotal(establishmentId: string, from: Date, to: Date): Promise<number> {
    const categories = Object.keys(AMORTIZED_CATEGORY_CYCLE_DAYS);
    const maxCycleDays = Math.max(...Object.values(AMORTIZED_CATEGORY_CYCLE_DAYS));
    const lookbackStart = new Date(from.getTime() - maxCycleDays * MS_PER_DAY);

    const expenses = await this.prisma.expense.findMany({
      where: { establishmentId, category: { in: categories }, expenseDate: { gte: lookbackStart, lte: to } },
      select: { amount: true, expenseDate: true, category: true },
    });

    let total = 0;
    for (const e of expenses) {
      const cycleDays = e.category ? AMORTIZED_CATEGORY_CYCLE_DAYS[e.category] : undefined;
      if (!cycleDays) continue;
      const coverageEnd = new Date(e.expenseDate.getTime() + cycleDays * MS_PER_DAY);
      const overlapStart = e.expenseDate > from ? e.expenseDate : from;
      const overlapEnd = coverageEnd < to ? coverageEnd : to;
      const overlapMs = overlapEnd.getTime() - overlapStart.getTime();
      if (overlapMs <= 0) continue;
      total += e.amount.toNumber() * (overlapMs / (cycleDays * MS_PER_DAY));
    }
    return total;
  }

  /** Pertes enregistrées sur `[from, to]`, même calcul de coût que `ReportsService.summary` (`effectiveUnitCost`). */
  private async lossLines(establishmentId: string, from: Date, to: Date): Promise<{ createdAt: Date; amount: number }[]> {
    const losses = await this.prisma.loss.findMany({
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
    });
    return losses.map((l) => ({ createdAt: l.createdAt, amount: l.quantity.toNumber() * effectiveUnitCost(l.product) }));
  }

  /**
   * Transforme une marge brute (`values`, une case par "case" — jour de la
   * semaine ou mois de l'année selon `bucketIndexOf`) en un bénéfice net
   * qui tient compte de TOUTES les natures de dépenses et des pertes
   * (décision utilisateur du 2026-09-13) :
   * - Les dépenses à cycle long (Loyer/Cie/Eau/Patentes) sont réparties au
   *   prorata du recouvrement (`amortizedOverheadTotal`) puis étalées à
   *   parts égales sur toutes les cases de `values` — aucune date précise
   *   ne leur est plus pertinente une fois réparties.
   * - Les autres natures (Salaires, Entretien, Bouteilles de gaz, Charbon,
   *   "Autre"...) et les pertes sont comptées en entier à leur date réelle,
   *   dans la case correspondante — "Marché" est explicitement exclue :
   *   déjà imputée ligne à ligne par `allocateMarcheCost`, la recompter ici
   *   la compterait deux fois.
   */
  private async applyNetProfitAdjustments(
    establishmentId: string,
    from: Date,
    to: Date,
    values: number[],
    bucketIndexOf: (date: Date) => number,
  ): Promise<void> {
    const [expenses, losses, amortizedTotal] = await Promise.all([
      this.expenseLines(establishmentId, from, to),
      this.lossLines(establishmentId, from, to),
      this.amortizedOverheadTotal(establishmentId, from, to),
    ]);

    const amortizedPerBucket = amortizedTotal / values.length;
    for (let i = 0; i < values.length; i++) {
      values[i] -= amortizedPerBucket;
    }
    for (const e of expenses) {
      if (e.category === 'Marché' || (e.category && AMORTIZED_CATEGORY_CYCLE_DAYS[e.category])) continue;
      values[bucketIndexOf(e.createdAt)] -= e.amount;
    }
    for (const l of losses) {
      values[bucketIndexOf(l.createdAt)] -= l.amount;
    }
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

  /**
   * "Bénéfice total" (pas les vues par catégorie/produit ci-dessous, voir le
   * commentaire au-dessus de `soldLines` : aucune façon correcte d'attribuer
   * une charge générale à un produit) — décision utilisateur du 2026-09-13 :
   * doit désormais tenir compte de TOUTES les natures de dépenses (pas
   * seulement "Marché") et des pertes enregistrées, pas seulement de la
   * marge brute. Voir `applyNetProfitAdjustments`.
   */
  async weeklyTotal(establishmentId: string, metric: ChartMetric, weekStart?: string) {
    const { from, to, monday } = this.weekRange(weekStart);
    const lines = await this.soldLines(establishmentId, from, to);
    const values = emptyWeek();
    for (const line of lines) {
      values[weekdayIndex(line.createdAt)] += valueOf(metric, line);
    }
    if (metric === 'profit') {
      await this.applyNetProfitAdjustments(establishmentId, from, to, values, weekdayIndex);
    }
    return this.buildWeekResponse(monday, [{ id: null, name: 'Total', values }]);
  }

  /**
   * `categoryIdsCsv` vide/absent : comportement historique — une série par
   * catégorie. `categoryIdsCsv` renseigné (une ou plusieurs catégories,
   * sélection multiple côté UI) : une seule série agrégée (somme jour par
   * jour de toutes les catégories choisies), pour répondre à "le calcul des
   * bénéfices/recettes selon les catégories sélectionnées" plutôt que
   * d'afficher chaque catégorie séparément.
   */
  async weeklyByCategory(establishmentId: string, metric: ChartMetric, weekStart?: string, categoryIdsCsv?: string) {
    const { from, to, monday } = this.weekRange(weekStart);
    const lines = await this.soldLines(establishmentId, from, to);
    const categoryIds = categoryIdsCsv ? categoryIdsCsv.split(',').filter((id) => id.length > 0) : [];

    if (categoryIds.length > 0) {
      const filtered = lines.filter((l) => l.categoryId != null && categoryIds.includes(l.categoryId));
      const names = [...new Set(filtered.map((l) => l.categoryName))];
      const values = emptyWeek();
      for (const line of filtered) {
        values[weekdayIndex(line.createdAt)] += valueOf(metric, line);
      }
      const name = names.length === 1 ? names[0] : `${categoryIds.length} catégories sélectionnées`;
      return this.buildWeekResponse(monday, [{ id: null, name, values }]);
    }

    const byKey = new Map<string, WeekSeries>();
    for (const line of lines) {
      const key = line.categoryId ?? '__none__';
      const entry = byKey.get(key) ?? { id: line.categoryId, name: line.categoryName, values: emptyWeek() };
      entry.values[weekdayIndex(line.createdAt)] += valueOf(metric, line);
      byKey.set(key, entry);
    }
    const series = [...byKey.values()].sort((a, b) => sumOf(b.values) - sumOf(a.values));
    return this.buildWeekResponse(monday, series);
  }

  async weeklyByProduct(
    establishmentId: string,
    metric: ChartMetric,
    weekStart?: string,
    productId?: string,
    productIdsCsv?: string,
  ) {
    const { from, to, monday } = this.weekRange(weekStart);
    const lines = await this.soldLines(establishmentId, from, to);
    const productIds = productIdsCsv ? productIdsCsv.split(',').filter((id) => id.length > 0) : [];

    // Sélection multiple (2026-09-22) : agrégée en une seule série, même
    // principe que weeklyByCategory. `productId` (singulier) reste accepté
    // pour compatibilité, prioritaire sur l'ancien filtre à un seul produit.
    if (productIds.length > 0) {
      const filtered = lines.filter((l) => productIds.includes(l.productId));
      const names = [...new Set(filtered.map((l) => l.productName))];
      const values = emptyWeek();
      for (const line of filtered) {
        values[weekdayIndex(line.createdAt)] += valueOf(metric, line);
      }
      const name = names.length === 1 ? names[0] : `${productIds.length} produits sélectionnés`;
      return this.buildWeekResponse(monday, [{ id: null, name, values }]);
    }

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
    if (metric === 'profit') {
      await this.applyNetProfitAdjustments(establishmentId, from, to, values, (date) => date.getMonth());
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
   * reconstruit les lots d'un ou plusieurs produits (sélection multiple,
   * obligatoirement de la même catégorie — voir plus bas) à partir de leur
   * historique complet de `StockMovement`, sans aucun schéma de lot dédié.
   * Contrairement aux autres graphiques de ce service, cette vue représente
   * l'état COURANT du stock (tout l'historique des produits, pas une période
   * bornée par le filtre Année de la page Graphiques) — un lot reçu il y a
   * plusieurs années peut rester actif aujourd'hui.
   *
   * Numérotation/visibilité des lots (décision utilisateur, 2026-09-10) : un
   * lot L00N doit correspondre à la commande N°N (catégories à prix par
   * casier : Bières, Vins, Sucreries) ou au marché N°N (catégories à prix
   * variable : Poulets, Poissons, Plats africains) qui l'a réellement
   * produit, et ne doit pas s'afficher si cette commande/ce marché n'existe
   * pas. `computeFifoLots` parse déjà ce numéro depuis le motif du mouvement
   * 'in' (`referenceNumber`, ex. "Commande n°1" → 1) ; ici on renumérote le
   * `code` du lot avec ce numéro et on écarte tout lot dont le numéro est
   * absent ou ne correspond à aucune commande/marché existant(e) pour cet
   * établissement. Les catégories hors de ces deux groupes (aucune connue à
   * ce jour) ne sont pas soumises à cette règle et gardent la numérotation
   * séquentielle historique.
   */
  /**
   * [productIds] peut désormais mélanger plusieurs catégories (tableau de
   * bord "Détail d'un produit" du module Graphiques, filtre Catégorie à
   * sélection multiple — demande utilisateur du 2026-09-17) : le gating
   * "numéro de marché"/"numéro de commande" (hasVariablePricing/
   * hasCasePricing) et la validation des numéros de référence se calculent
   * donc par PRODUIT, selon sa propre catégorie, plutôt qu'en supposant une
   * catégorie unique pour toute la sélection.
   */
  async stockLots(establishmentId: string, productIds: string[]) {
    const products = await this.prisma.product.findMany({
      where: { id: { in: productIds }, establishmentId },
      select: {
        id: true,
        name: true,
        categoryId: true,
        category: { select: { name: true, hasCasePricing: true, hasVariablePricing: true } },
      },
    });
    if (products.length !== productIds.length) {
      throw new NotFoundException('Un ou plusieurs produits sont introuvables pour cet établissement');
    }

    const movements = await this.prisma.stockMovement.findMany({
      where: { productId: { in: productIds } },
      orderBy: { createdAt: 'asc' },
      select: { productId: true, type: true, quantity: true, createdAt: true, reason: true },
    });

    const lotsByProduct = new Map<string, StockLot[]>();
    for (const product of products) {
      const productMovements = movements
        .filter((m) => m.productId === product.id)
        .map((m) => ({
          type: m.type as StockLotMovementType,
          quantity: m.quantity.toNumber(),
          createdAt: m.createdAt,
          reason: m.reason,
        }));
      lotsByProduct.set(product.id, computeFifoLots(productMovements));
    }

    // Un seul aller-retour "Marché" et un seul "Purchase", même si plusieurs
    // produits de catégories différentes sont sélectionnés à la fois.
    const marketNumbersToCheck = new Set<number>();
    const orderNumbersToCheck = new Set<number>();
    for (const product of products) {
      if (!product.category?.hasCasePricing && !product.category?.hasVariablePricing) continue;
      const target = product.category.hasVariablePricing ? marketNumbersToCheck : orderNumbersToCheck;
      for (const lot of lotsByProduct.get(product.id) ?? []) {
        if (lot.referenceNumber != null) target.add(lot.referenceNumber);
      }
    }
    const [marches, purchases] = await Promise.all([
      marketNumbersToCheck.size > 0
        ? this.prisma.expense.findMany({
            where: { establishmentId, category: 'Marché', marketNumber: { in: [...marketNumbersToCheck] } },
            select: { marketNumber: true },
          })
        : Promise.resolve([]),
      orderNumbersToCheck.size > 0
        ? this.prisma.purchase.findMany({
            where: { establishmentId, status: 'received', orderNumber: { in: [...orderNumbersToCheck] } },
            select: { orderNumber: true },
          })
        : Promise.resolve([]),
    ]);
    const validMarketNumbers = new Set(marches.map((m) => m.marketNumber).filter((n): n is number => n != null));
    const validOrderNumbers = new Set(purchases.map((p) => p.orderNumber).filter((n): n is number => n != null));

    type ProductStockLot = StockLot & { productId: string; productName: string };
    const allLots: ProductStockLot[] = [];
    for (const product of products) {
      const gated = Boolean(product.category?.hasCasePricing || product.category?.hasVariablePricing);
      const validNumbers = product.category?.hasVariablePricing ? validMarketNumbers : validOrderNumbers;
      const productLots: ProductStockLot[] = [];
      let hiddenRemaining = 0;
      let hiddenLatestDate: Date | null = null;
      for (const lot of lotsByProduct.get(product.id) ?? []) {
        if (gated) {
          if (lot.referenceNumber == null) {
            hiddenRemaining += lot.remainingQuantity;
            if (!hiddenLatestDate || lot.receivedAt > hiddenLatestDate) hiddenLatestDate = lot.receivedAt;
            continue;
          }
          if (!validNumbers.has(lot.referenceNumber)) continue;
          productLots.push({ ...lot, code: `L${String(lot.referenceNumber).padStart(3, '0')}`, productId: product.id, productName: product.name });
        } else {
          productLots.push({ ...lot, productId: product.id, productName: product.name });
        }
      }
      // Le stock restant d'un lot sans N° de commande (entrée/correction manuelle,
      // ex. « Ajustement suite au point… ») est rattaché au dernier lot visible
      // du produit : la somme des lots reste égale au stock actuel (2026-09-20).
      // Ajouté à `receivedQuantity` ET `remainingQuantity` — pas seulement au
      // second — sinon un lot déjà bien entamé mais peu consommé (restant
      // proche du reçu) affiche un `consumedQuantity` négatif dès que le
      // stock orphelin le pousse au-dessus de son reçu d'origine (bug réel
      // constaté en production sur Chill/Rhino, 2026-09-25 : Consommé -1).
      // Sans lot visible pour l'accueillir (aucune commande valide pour ce
      // produit, ex. commande supprimée depuis), un lot synthétique est créé
      // plutôt que de silencieusement perdre ce stock des totaux.
      const target = productLots[productLots.length - 1];
      if (hiddenRemaining > 0) {
        if (target) {
          target.receivedQuantity += hiddenRemaining;
          target.remainingQuantity += hiddenRemaining;
          target.consumedQuantity = target.receivedQuantity - target.remainingQuantity;
          target.status = 'actif';
        } else {
          productLots.push({
            code: 'Ajustement',
            referenceNumber: null,
            receivedAt: hiddenLatestDate ?? new Date(),
            receivedQuantity: hiddenRemaining,
            consumedQuantity: 0,
            lossQuantity: 0,
            remainingQuantity: hiddenRemaining,
            status: 'actif',
            productId: product.id,
            productName: product.name,
          });
        }
      }
      allLots.push(...productLots);
    }
    allLots.sort((a, b) => a.receivedAt.getTime() - b.receivedAt.getTime());
    const activeLots = allLots.filter((lot) => lot.status === 'actif');

    return {
      productIds: products.map((p) => p.id),
      productNames: products.map((p) => p.name),
      activeLots,
      historyLots: allLots,
      totalActiveUnits: activeLots.reduce((sum, lot) => sum + lot.remainingQuantity, 0),
    };
  }

  /**
   * Listing "Stock actif" (module Stock, bouton d'export réservé au Super
   * Administrateur — demande utilisateur du 2026-09-25) : un produit = une
   * ligne, agrégée sur ses seuls lots FIFO de statut `'actif'`
   * (`computeFifoLots`, même critère que l'onglet "Lots actifs" de Graphiques
   * > Stock > Détail d'un produit — un lot devient `'epuise'` dès que sa
   * quantité restante atteint 0, voir `stock-lots.ts`). Produits sans aucun
   * lot actif (jamais approvisionnés, ou entièrement épuisés) absents du
   * résultat — ce listing ne porte que sur le stock réellement présent.
   *
   * Catégories à prix variable (Plats africains/Poissons/Poulets,
   * `hasVariablePricing`) **toujours exclues** — ni prix d'achat ni prix de
   * vente fixes en catalogue pour ces produits, les colonnes Prix
   * d'achat/Recette/Bénéfice n'auraient aucun sens. `categoryIds`, s'il est
   * fourni, restreint davantage la sélection aux catégories listées
   * (sélection multiple côté Flutter) ; absent/vide = toutes les catégories
   * éligibles.
   *
   * `lossQuantity` d'un lot est une **part** de `consumedQuantity` (voir
   * `StockLot`), pas un total distinct : `consommé` ci-dessous est donc net
   * des pertes (`consumedQuantity - lossQuantity`) pour que les colonnes
   * s'additionnent proprement (`reçue = consommé + perdu + restant`), plutôt
   * que de compter deux fois la part perdue.
   *
   * Chaque quantité vendable est valorisée au même prix de vente unitaire que
   * les pertes (`salePrice` sinon `referenceSalePrice` sinon 0 — voir
   * `lossUnitSalePrice`, `reports/loss-revenue.ts`), cohérent avec le "prix de
   * vente attendu du stock actuel" déjà affiché ailleurs dans le module Stock.
   * `purchaseValue`/`profit` utilisent le même coût unitaire que les
   * graphiques Bénéfices (`effectiveUnitCost`, `catalog/product-cost.util.ts`).
   */
  async activeStockListing(establishmentId: string, categoryIds?: string[]): Promise<
    {
      productId: string;
      productName: string;
      receivedQuantity: number;
      purchaseValue: number;
      receivedRevenue: number;
      consumedQuantity: number;
      consumedRevenue: number;
      lossQuantity: number;
      lossRevenue: number;
      remainingQuantity: number;
      remainingRevenue: number;
      profit: number;
    }[]
  > {
    const allProducts = await this.prisma.product.findMany({
      where: { establishmentId, status: 'active' },
      select: {
        id: true,
        name: true,
        categoryId: true,
        salePrice: true,
        referenceSalePrice: true,
        purchasePrice: true,
        bottlesPerCase: true,
        purchasePricePerCase: true,
        category: { select: { hasCasePricing: true, hasVariablePricing: true } },
      },
      orderBy: { name: 'asc' },
    });
    const products = allProducts.filter((p) => {
      if (p.category?.hasVariablePricing) return false;
      if (categoryIds && categoryIds.length > 0) return p.categoryId != null && categoryIds.includes(p.categoryId);
      return true;
    });

    const movements = await this.prisma.stockMovement.findMany({
      where: { productId: { in: products.map((p) => p.id) } },
      orderBy: { createdAt: 'asc' },
      select: { productId: true, type: true, quantity: true, createdAt: true, reason: true },
    });

    const rows: {
      productId: string;
      productName: string;
      receivedQuantity: number;
      purchaseValue: number;
      receivedRevenue: number;
      consumedQuantity: number;
      consumedRevenue: number;
      lossQuantity: number;
      lossRevenue: number;
      remainingQuantity: number;
      remainingRevenue: number;
      profit: number;
    }[] = [];
    for (const product of products) {
      const productMovements = movements
        .filter((m) => m.productId === product.id)
        .map((m) => ({ type: m.type as StockLotMovementType, quantity: m.quantity.toNumber(), createdAt: m.createdAt, reason: m.reason }));
      const activeLots = computeFifoLots(productMovements).filter((lot) => lot.status === 'actif');
      if (activeLots.length === 0) continue;

      const receivedQuantity = activeLots.reduce((sum, lot) => sum + lot.receivedQuantity, 0);
      const lossQuantity = activeLots.reduce((sum, lot) => sum + lot.lossQuantity, 0);
      const totalConsumed = activeLots.reduce((sum, lot) => sum + lot.consumedQuantity, 0);
      const consumedQuantity = totalConsumed - lossQuantity;
      const remainingQuantity = activeLots.reduce((sum, lot) => sum + lot.remainingQuantity, 0);
      const unitPrice = product.salePrice?.toNumber() ?? product.referenceSalePrice?.toNumber() ?? 0;
      const unitCost = effectiveUnitCost(product);
      const purchaseValue = receivedQuantity * unitCost;
      const receivedRevenue = receivedQuantity * unitPrice;

      rows.push({
        productId: product.id,
        productName: product.name,
        receivedQuantity,
        purchaseValue,
        receivedRevenue,
        consumedQuantity,
        consumedRevenue: consumedQuantity * unitPrice,
        lossQuantity,
        lossRevenue: lossQuantity * unitPrice,
        remainingQuantity,
        remainingRevenue: remainingQuantity * unitPrice,
        profit: receivedRevenue - purchaseValue,
      });
    }
    return rows;
  }

  /**
   * Export PDF du listing `activeStockListing` ci-dessus — tableau à
   * quadrillage complet (`drawPdfTable`, même principe que les exports du
   * module Rapports), format paysage plutôt que portrait vu le nombre de
   * colonnes (11). Une ligne TOTAL somme chaque colonne.
   */
  async activeStockListingPdf(establishmentId: string, categoryIds?: string[]): Promise<{ buffer: Buffer; filename: string }> {
    const rows = await this.activeStockListing(establishmentId, categoryIds);

    const totals = rows.reduce(
      (acc, r) => ({
        receivedQuantity: acc.receivedQuantity + r.receivedQuantity,
        purchaseValue: acc.purchaseValue + r.purchaseValue,
        receivedRevenue: acc.receivedRevenue + r.receivedRevenue,
        consumedQuantity: acc.consumedQuantity + r.consumedQuantity,
        consumedRevenue: acc.consumedRevenue + r.consumedRevenue,
        lossQuantity: acc.lossQuantity + r.lossQuantity,
        lossRevenue: acc.lossRevenue + r.lossRevenue,
        remainingQuantity: acc.remainingQuantity + r.remainingQuantity,
        remainingRevenue: acc.remainingRevenue + r.remainingRevenue,
        profit: acc.profit + r.profit,
      }),
      {
        receivedQuantity: 0,
        purchaseValue: 0,
        receivedRevenue: 0,
        consumedQuantity: 0,
        consumedRevenue: 0,
        lossQuantity: 0,
        lossRevenue: 0,
        remainingQuantity: 0,
        remainingRevenue: 0,
        profit: 0,
      },
    );

    const doc = new PDFDocument({ margin: 30, size: 'A4', layout: 'landscape' });
    const chunks: Buffer[] = [];
    doc.on('data', (chunk: Buffer) => chunks.push(chunk));
    const done = new Promise<void>((resolve) => doc.on('end', () => resolve()));

    doc.fontSize(14).font('Helvetica-Bold').text('Stock actif', { align: 'left' });
    doc.fontSize(10).font('Helvetica').text(`${rows.length} produit${rows.length > 1 ? 's' : ''}`);
    doc.moveDown(0.5);

    const qty = (n: number) => (Number.isInteger(n) ? n.toString() : n.toFixed(2));

    drawPdfTable(
      doc,
      [
        { header: 'Produit', width: 105 },
        { header: 'Qté reçue', width: 55, align: 'right' },
        { header: "Prix d'achat qté reçue (FCFA)", width: 85, align: 'right' },
        { header: 'Recette qté reçue (FCFA)', width: 80, align: 'right' },
        { header: 'Consommé', width: 55, align: 'right' },
        { header: 'Recette consommé (FCFA)', width: 80, align: 'right' },
        { header: 'Perdu', width: 45, align: 'right' },
        { header: 'Recette perdue (FCFA)', width: 75, align: 'right' },
        { header: 'Restant', width: 50, align: 'right' },
        { header: 'Recette stock (FCFA)', width: 75, align: 'right' },
        { header: 'Bénéfice (FCFA)', width: 75, align: 'right' },
      ],
      [
        ...rows.map((r) => [
          r.productName,
          qty(r.receivedQuantity),
          formatFcfa(r.purchaseValue),
          formatFcfa(r.receivedRevenue),
          qty(r.consumedQuantity),
          formatFcfa(r.consumedRevenue),
          qty(r.lossQuantity),
          formatFcfa(r.lossRevenue),
          qty(r.remainingQuantity),
          formatFcfa(r.remainingRevenue),
          formatFcfa(r.profit),
        ]),
        [
          'TOTAL',
          qty(totals.receivedQuantity),
          formatFcfa(totals.purchaseValue),
          formatFcfa(totals.receivedRevenue),
          qty(totals.consumedQuantity),
          formatFcfa(totals.consumedRevenue),
          qty(totals.lossQuantity),
          formatFcfa(totals.lossRevenue),
          qty(totals.remainingQuantity),
          formatFcfa(totals.remainingRevenue),
          formatFcfa(totals.profit),
        ],
      ],
      { boldRowIndexes: new Set([rows.length]) },
    );

    doc.end();
    await done;
    const buffer = Buffer.concat(chunks);
    return { buffer, filename: 'Stock actif.pdf' };
  }

  /**
   * Listing "Repas" (module Graphiques > Bénéfices, bouton d'export — demande
   * utilisateur du 2026-09-25) : cumule les trois catégories à prix variable
   * (Plats africains/Poissons/Poulets, `hasVariablePricing`) en une seule
   * ligne "Repas" — pas de ventilation par catégorie ni par produit. Portée :
   * tout l'historique (pas de filtre de période, décision utilisateur — même
   * convention que le listing Stock actif).
   *
   * - `marketCost` : somme de toutes les dépenses de catégorie `'Marché'`
   *   **et** `'Bouteilles de gaz'` — les deux seules natures de dépense
   *   directement rattachables à l'approvisionnement des repas (le carburant
   *   de cuisson, comme le marché lui-même, n'a pas d'autre destination dans
   *   ce commerce).
   * - `currentRevenue` : somme des lignes de vente (`SaleItem`, ventes non
   *   annulées) dont le produit appartient à une catégorie `hasVariablePricing`
   *   — même filtre que `ReportsService.paymentCategoryBreakdown`
   *   (groupe "Plats").
   * - `profit = currentRevenue - marketCost` (confirmé explicitement par
   *   l'utilisateur le 2026-09-25 — la formule "dépenses − recettes" du
   *   message d'origine aurait donné un bénéfice négatif pour une activité
   *   rentable, incohérent avec le `rate` en pourcentage attendu positif).
   * - `rate = profit × 100 / marketCost` (0 si `marketCost` est nul, pour
   *   éviter une division par zéro).
   */
  async mealsProfitListing(establishmentId: string): Promise<{
    marketCost: number;
    currentRevenue: number;
    profit: number;
    rate: number;
  }> {
    const [expenses, saleItems] = await Promise.all([
      this.prisma.expense.findMany({
        where: { establishmentId, category: { in: ['Marché', 'Bouteilles de gaz'] } },
        select: { amount: true },
      }),
      this.prisma.saleItem.findMany({
        where: {
          sale: { establishmentId, voidedAt: null },
          product: { category: { hasVariablePricing: true } },
        },
        select: { quantity: true, unitPrice: true },
      }),
    ]);

    const marketCost = expenses.reduce((sum, e) => sum + e.amount.toNumber(), 0);
    const currentRevenue = saleItems.reduce((sum, i) => sum + i.quantity.toNumber() * i.unitPrice.toNumber(), 0);
    const profit = currentRevenue - marketCost;
    const rate = marketCost > 0 ? (profit * 100) / marketCost : 0;

    return { marketCost, currentRevenue, profit, rate };
  }

  /**
   * Export PDF du listing `mealsProfitListing` ci-dessus — tableau à
   * quadrillage complet (`drawPdfTable`), exactement deux lignes de données
   * ("Repas" puis "TOTAL", cette dernière identique à la première puisqu'il
   * n'y a qu'une seule ligne agrégée — même convention "toujours une ligne
   * TOTAL" que les autres listings de l'application).
   */
  async mealsProfitListingPdf(establishmentId: string): Promise<{ buffer: Buffer; filename: string }> {
    const { marketCost, currentRevenue, profit, rate } = await this.mealsProfitListing(establishmentId);

    const doc = new PDFDocument({ margin: 30, size: 'A4' });
    const chunks: Buffer[] = [];
    doc.on('data', (chunk: Buffer) => chunks.push(chunk));
    const done = new Promise<void>((resolve) => doc.on('end', () => resolve()));

    doc.fontSize(14).font('Helvetica-Bold').text('Repas', { align: 'left' });
    doc.fontSize(10).font('Helvetica').text('Plats africains, Poissons, Poulets — cumulés');
    doc.moveDown(0.5);

    const rate2 = `${rate.toFixed(2)} %`;

    drawPdfTable(
      doc,
      [
        { header: 'Repas', width: 100 },
        { header: 'Prix marché (FCFA)', width: 130, align: 'right' },
        { header: 'Recette actuelle (FCFA)', width: 130, align: 'right' },
        { header: 'Bénéfice (FCFA)', width: 110, align: 'right' },
        { header: 'Taux', width: 65, align: 'right' },
      ],
      [
        ['Repas', formatFcfa(marketCost), formatFcfa(currentRevenue), formatFcfa(profit), rate2],
        ['TOTAL', formatFcfa(marketCost), formatFcfa(currentRevenue), formatFcfa(profit), rate2],
      ],
      { boldRowIndexes: new Set([1]) },
    );

    doc.end();
    await done;
    const buffer = Buffer.concat(chunks);
    return { buffer, filename: 'Repas.pdf' };
  }

  /** "Top des produits épuisés" (sous-module Stock) : produits actifs en rupture (stockQuantity ≤ 0), triés par ordre alphabétique croissant — seul critère "croissant" disponible en l'absence d'un autre axe numérique demandé. */
  async outOfStockProducts(establishmentId: string) {
    const products = await this.prisma.product.findMany({
      where: { establishmentId, status: 'active', stockQuantity: { lte: 0 } },
      select: { id: true, name: true, stockQuantity: true, category: { select: { name: true } } },
      orderBy: { name: 'asc' },
    });
    return products.map((p) => ({
      id: p.id,
      name: p.name,
      categoryName: p.category?.name ?? 'Sans catégorie',
      stockQuantity: p.stockQuantity.toNumber(),
    }));
  }

  // ── Sous-module "Dépenses" ────────────────────────────────────────────
  //
  // Contrairement à Recettes/Bénéfices, une dépense n'a ni produit ni
  // catégorie de PRODUIT — seulement sa propre "nature" (Loyer, Eau, ...,
  // voir kPredefinedExpenseCategories côté Flutter). Il n'existe donc pas
  // de graphique "par produit" ici (4 graphiques au lieu de 5) ; "par
  // catégorie" utilise cette nature de dépense comme clé de regroupement.
  // Périodicité (récurrente/ponctuelle) délibérément ignorée dans ces
  // graphiques : c'est une étiquette informative, pas un axe d'analyse
  // demandé.

  private async expenseLines(establishmentId: string, from: Date, to: Date) {
    const expenses = await this.prisma.expense.findMany({
      where: { establishmentId, expenseDate: { gte: from, lte: to } },
      select: { amount: true, expenseDate: true, category: true },
    });
    return expenses.map((e) => ({
      createdAt: e.expenseDate,
      amount: e.amount.toNumber(),
      category: e.category?.trim() || null,
    }));
  }

  async expensesWeeklyTotal(establishmentId: string, weekStart?: string) {
    const { from, to, monday } = this.weekRange(weekStart);
    const lines = await this.expenseLines(establishmentId, from, to);
    const values = emptyWeek();
    for (const line of lines) {
      values[weekdayIndex(line.createdAt)] += line.amount;
    }
    return this.buildWeekResponse(monday, [{ id: null, name: 'Total', values }]);
  }

  async expensesWeeklyByCategory(establishmentId: string, weekStart?: string, categoriesCsv?: string) {
    const { from, to, monday } = this.weekRange(weekStart);
    const lines = await this.expenseLines(establishmentId, from, to);
    const categories = categoriesCsv ? categoriesCsv.split(',').filter((c) => c.length > 0) : [];

    if (categories.length > 0) {
      const filtered = lines.filter((l) => l.category != null && categories.includes(l.category));
      const values = emptyWeek();
      for (const line of filtered) {
        values[weekdayIndex(line.createdAt)] += line.amount;
      }
      const name = categories.length === 1 ? categories[0] : `${categories.length} catégories sélectionnées`;
      return this.buildWeekResponse(monday, [{ id: null, name, values }]);
    }

    const byKey = new Map<string, WeekSeries>();
    for (const line of lines) {
      const key = line.category ?? '__none__';
      const name = line.category ?? 'Sans catégorie';
      const entry = byKey.get(key) ?? { id: line.category, name, values: emptyWeek() };
      entry.values[weekdayIndex(line.createdAt)] += line.amount;
      byKey.set(key, entry);
    }
    const series = [...byKey.values()].sort((a, b) => sumOf(b.values) - sumOf(a.values));
    return this.buildWeekResponse(monday, series);
  }

  async expensesMonthly(establishmentId: string, year: number) {
    const from = new Date(year, 0, 1, 0, 0, 0, 0);
    const to = new Date(year, 11, 31, 23, 59, 59, 999);
    const lines = await this.expenseLines(establishmentId, from, to);
    const values = new Array(12).fill(0) as number[];
    for (const line of lines) {
      values[line.createdAt.getMonth()] += line.amount;
    }
    return { year, months: MONTH_LABELS.map((month, i) => ({ month, value: values[i] })) };
  }

  /** Classement des natures de dépenses (§ "Top dépenses"), même plafond de 10 lignes que les autres classements de ce service. */
  async expensesTop(establishmentId: string, from: Date, to: Date) {
    const lines = await this.expenseLines(establishmentId, from, to);
    const agg = new Map<string, { id: string | null; name: string; value: number }>();
    for (const line of lines) {
      const key = line.category ?? '__none__';
      const name = line.category ?? 'Sans catégorie';
      const entry = agg.get(key) ?? { id: line.category, name, value: 0 };
      entry.value += line.amount;
      agg.set(key, entry);
    }
    const items = [...agg.values()].sort((a, b) => b.value - a.value).slice(0, 10);
    return { from: from.toISOString(), to: to.toISOString(), groupBy: 'category', items };
  }
}

function sumOf(values: number[]): number {
  return values.reduce((sum, v) => sum + v, 0);
}
