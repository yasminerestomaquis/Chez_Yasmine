import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { effectiveUnitCost } from '../catalog/product-cost.util.js';
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
    if (new Set(products.map((p) => p.categoryId)).size > 1) {
      throw new BadRequestException('La sélection multiple ne peut porter que sur des produits de la même catégorie');
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

    const category = products[0]?.category;
    const gated = Boolean(category?.hasCasePricing || category?.hasVariablePricing);
    let validNumbers = new Set<number>();
    if (gated) {
      const referenceNumbers = [
        ...new Set([...lotsByProduct.values()].flat().map((l) => l.referenceNumber).filter((n): n is number => n != null)),
      ];
      if (referenceNumbers.length > 0) {
        if (category?.hasVariablePricing) {
          const marches = await this.prisma.expense.findMany({
            where: { establishmentId, category: 'Marché', marketNumber: { in: referenceNumbers } },
            select: { marketNumber: true },
          });
          validNumbers = new Set(marches.map((m) => m.marketNumber).filter((n): n is number => n != null));
        } else {
          const purchases = await this.prisma.purchase.findMany({
            where: { establishmentId, orderNumber: { in: referenceNumbers } },
            select: { orderNumber: true },
          });
          validNumbers = new Set(purchases.map((p) => p.orderNumber).filter((n): n is number => n != null));
        }
      }
    }

    type ProductStockLot = StockLot & { productId: string; productName: string };
    const allLots: ProductStockLot[] = [];
    for (const product of products) {
      for (const lot of lotsByProduct.get(product.id) ?? []) {
        if (gated) {
          if (lot.referenceNumber == null || !validNumbers.has(lot.referenceNumber)) continue;
          allLots.push({ ...lot, code: `L${String(lot.referenceNumber).padStart(3, '0')}`, productId: product.id, productName: product.name });
        } else {
          allLots.push({ ...lot, productId: product.id, productName: product.name });
        }
      }
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

  async expensesWeeklyByCategory(establishmentId: string, weekStart?: string, category?: string) {
    const { from, to, monday } = this.weekRange(weekStart);
    const lines = await this.expenseLines(establishmentId, from, to);
    const filtered = category ? lines.filter((l) => l.category === category) : lines;

    const byKey = new Map<string, WeekSeries>();
    for (const line of filtered) {
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
