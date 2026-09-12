import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import { ActivityNotifierService } from '../notifications/activity-notifier.service.js';
import type { CreateExpenseDto, UpdateExpenseDto } from './dto/expense.dto.js';

export interface ExpensePeriodQuery {
  period: 'year' | 'month' | 'week';
  year: number;
  /** 1-12, requis seulement pour period === 'month'. */
  month?: number;
  /** ISO date (n'importe quel jour de la semaine visée), requis seulement pour period === 'week'. */
  weekOf?: string;
}

export interface ExpensePeriodRange {
  from: Date;
  to: Date;
}

/**
 * Résolution de bornes propre à ce module — dupliquée depuis un besoin
 * similaire dans ReportsService.resolveRange plutôt que factorisée, pour ne
 * jamais toucher reports.service.ts (contrainte explicite : ne pas modifier
 * le comportement d'un autre module). Lundi..dimanche pour "week", même
 * convention que ChartsService.mondayOf.
 */
export function resolveExpensePeriodRange(query: ExpensePeriodQuery): ExpensePeriodRange {
  if (query.period === 'year') {
    return { from: new Date(query.year, 0, 1, 0, 0, 0, 0), to: new Date(query.year, 11, 31, 23, 59, 59, 999) };
  }
  if (query.period === 'month') {
    const month = query.month ?? 1;
    return { from: new Date(query.year, month - 1, 1, 0, 0, 0, 0), to: new Date(query.year, month, 0, 23, 59, 59, 999) };
  }
  const reference = query.weekOf ? new Date(query.weekOf) : new Date();
  const weekdayIndex = (reference.getDay() + 6) % 7; // lundi = 0
  const monday = new Date(reference);
  monday.setHours(0, 0, 0, 0);
  monday.setDate(monday.getDate() - weekdayIndex);
  const sunday = new Date(monday);
  sunday.setDate(sunday.getDate() + 6);
  sunday.setHours(23, 59, 59, 999);
  return { from: monday, to: sunday };
}

/** Période équivalente immédiatement précédente — même durée, bornée juste avant `range.from`. */
function previousRange({ from, to }: ExpensePeriodRange): ExpensePeriodRange {
  const durationMs = to.getTime() - from.getTime();
  const previousTo = new Date(from.getTime() - 1);
  const previousFrom = new Date(previousTo.getTime() - durationMs);
  return { from: previousFrom, to: previousTo };
}

@Injectable()
export class ExpensesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly activityNotifier: ActivityNotifierService,
  ) {}

  list(establishmentId: string, range?: { from?: string; to?: string }) {
    return this.prisma.expense.findMany({
      where: {
        establishmentId,
        ...(range?.from || range?.to
          ? {
              expenseDate: {
                gte: range?.from ? new Date(range.from) : undefined,
                lte: range?.to ? new Date(range.to) : undefined,
              },
            }
          : {}),
      },
      orderBy: { expenseDate: 'desc' },
    });
  }

  /** Retourne le prochain N° de marché suggéré (toutes dépenses "Marché" de l'établissement) — simple convenance, jamais imposé côté serveur, même principe que PurchasesService.nextOrderNumber. */
  async nextMarketNumber(establishmentId: string): Promise<number> {
    const last = await this.prisma.expense.findFirst({
      where: { establishmentId, category: 'Marché' },
      orderBy: { marketNumber: 'desc' },
      select: { marketNumber: true },
    });
    return (last?.marketNumber ?? 0) + 1;
  }

  async create(establishmentId: string, dto: CreateExpenseDto) {
    // Idempotent replay — même motif que SalesService.create : une dépense
    // saisie hors ligne peut être renvoyée plusieurs fois par la file de
    // synchronisation sans créer de doublon.
    if (dto.id) {
      const existing = await this.prisma.expense.findFirst({ where: { id: dto.id, establishmentId } });
      if (existing) return existing;
    }
    const expense = await this.prisma.expense.create({
      data: {
        id: dto.id,
        establishmentId,
        label: dto.label,
        category: dto.category,
        amount: dto.amount,
        expenseDate: dto.expenseDate ? new Date(dto.expenseDate) : undefined,
        periodicity: dto.periodicity ?? 'one_off',
        note: dto.note,
        marketNumber: dto.marketNumber,
      },
    });
    await this.activityNotifier.notify(
      establishmentId,
      'Nouvelle dépense',
      `${dto.label} — ${dto.amount.toLocaleString('fr-FR')} FCFA${dto.category ? ` (${dto.category})` : ''}`,
    );
    return expense;
  }

  async update(establishmentId: string, expenseId: string, dto: UpdateExpenseDto) {
    const { count } = await this.prisma.expense.updateMany({
      where: { id: expenseId, establishmentId },
      data: {
        label: dto.label,
        category: dto.category,
        amount: dto.amount,
        note: dto.note,
        expenseDate: dto.expenseDate ? new Date(dto.expenseDate) : undefined,
        periodicity: dto.periodicity,
        marketNumber: dto.marketNumber,
      },
    });
    if (count === 0) {
      throw new NotFoundException('Dépense introuvable pour cet établissement');
    }
    return this.prisma.expense.findUniqueOrThrow({ where: { id: expenseId } });
  }

  async remove(establishmentId: string, expenseId: string): Promise<void> {
    const { count } = await this.prisma.expense.deleteMany({ where: { id: expenseId, establishmentId } });
    if (count === 0) {
      throw new NotFoundException('Dépense introuvable pour cet établissement');
    }
  }

  /**
   * Synthèse pour l'onglet "Vue d'ensemble" : 4 totaux (dépenses totales,
   * Salaires, Marché, "charges fixes" = tout le reste), comparaison à la
   * période équivalente précédente, et répartition par nature pour le
   * donut chart. `category` regroupe null/vide sous "Autre".
   */
  async summary(establishmentId: string, query: ExpensePeriodQuery) {
    const range = resolveExpensePeriodRange(query);
    const previous = previousRange(range);

    const [expenses, previousExpenses] = await Promise.all([
      this.prisma.expense.findMany({
        where: { establishmentId, expenseDate: { gte: range.from, lte: range.to } },
        // Tous les champs de `Expense.fromJson` côté Flutter (Task 9) sont
        // nécessaires ici : `recent` (ci-dessous) est directement désérialisé
        // en `List<Expense>`, pas juste { category, amount, expenseDate } —
        // un select trop étroit ferait planter `Expense.fromJson` (id/label
        // manquants) au premier rendu de "Dernières dépenses" (Task 12).
        select: {
          id: true,
          label: true,
          category: true,
          amount: true,
          expenseDate: true,
          periodicity: true,
          note: true,
          marketNumber: true,
          paymentMethod: true,
          status: true,
        },
      }),
      this.prisma.expense.findMany({
        where: { establishmentId, expenseDate: { gte: previous.from, lte: previous.to } },
        select: { amount: true },
      }),
    ]);

    const sum = (list: { amount: { toNumber(): number } }[]) => list.reduce((s, e) => s + e.amount.toNumber(), 0);
    const totalAmount = sum(expenses);
    const totalSalaries = sum(expenses.filter((e) => e.category === 'Salaires'));
    const totalMarket = sum(expenses.filter((e) => e.category === 'Marché'));
    const totalFixedCharges = totalAmount - totalSalaries - totalMarket;
    const previousTotalAmount = sum(previousExpenses);
    const changePercent = previousTotalAmount > 0 ? ((totalAmount - previousTotalAmount) / previousTotalAmount) * 100 : null;

    const byCategoryMap = new Map<string, number>();
    for (const e of expenses) {
      const key = e.category?.trim() || 'Autre';
      byCategoryMap.set(key, (byCategoryMap.get(key) ?? 0) + e.amount.toNumber());
    }
    const byCategory = [...byCategoryMap.entries()].map(([category, amount]) => ({ category, amount }));

    return {
      from: range.from,
      to: range.to,
      totalAmount,
      totalSalaries,
      totalMarket,
      totalFixedCharges,
      previousTotalAmount,
      changePercent,
      byCategory,
      recent: [...expenses]
        .sort((a, b) => b.expenseDate.getTime() - a.expenseDate.getTime())
        .slice(0, 8),
    };
  }
}
