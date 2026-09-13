import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import ExcelJS from 'exceljs';
import { PrismaService } from '../prisma/prisma.service.js';
import { ActivityNotifierService } from '../notifications/activity-notifier.service.js';
import type { CreateExpenseDto, UpdateExpenseDto, ExpenseHistoryQueryDto } from './dto/expense.dto.js';

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
    // La nature "Salaires" ne doit jamais être saisie à la main : son
    // montant doit toujours provenir d'un paiement de paie réel
    // (PayrollService.pay(), voir docs/api/expenses.md) — sans cette garde,
    // rien n'empêchait de créer une dépense "Salaires" fictive en plus de
    // celle générée automatiquement.
    if (dto.category === 'Salaires') {
      throw new BadRequestException(
        'La nature "Salaires" est réservée aux paiements de paie — utilisez l\'onglet Salaires pour payer les employés.',
      );
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

  /**
   * Une dépense générée automatiquement par un paiement de paie
   * (`payrollRunId` non nul) ne peut être ni modifiée ni supprimée depuis ce
   * service générique — la corriger ici désynchroniserait silencieusement
   * le `PayrollRun` correspondant (voir docs/api/expenses.md).
   */
  private async findOwnExpenseOrThrow(establishmentId: string, expenseId: string) {
    const existing = await this.prisma.expense.findFirst({ where: { id: expenseId, establishmentId } });
    if (!existing) {
      throw new NotFoundException('Dépense introuvable pour cet établissement');
    }
    return existing;
  }

  async update(establishmentId: string, expenseId: string, dto: UpdateExpenseDto) {
    const existing = await this.findOwnExpenseOrThrow(establishmentId, expenseId);
    if (existing.payrollRunId) {
      throw new BadRequestException(
        'Cette dépense provient d\'un paiement de salaires — elle ne peut être modifiée que depuis l\'onglet Salaires.',
      );
    }
    return this.prisma.expense.update({
      where: { id: expenseId },
      data: {
        label: dto.label,
        category: dto.category,
        amount: dto.amount,
        note: dto.note,
        expenseDate: dto.expenseDate ? new Date(dto.expenseDate) : undefined,
        periodicity: dto.periodicity,
        marketNumber: dto.marketNumber,
        paymentMethod: dto.paymentMethod,
        status: dto.status,
      },
    });
  }

  async remove(establishmentId: string, expenseId: string): Promise<void> {
    const existing = await this.findOwnExpenseOrThrow(establishmentId, expenseId);
    if (existing.payrollRunId) {
      throw new BadRequestException(
        'Cette dépense provient d\'un paiement de salaires — annulez plutôt la paie correspondante depuis l\'onglet Salaires.',
      );
    }
    await this.prisma.expense.delete({ where: { id: expenseId } });
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
        select: { amount: true, category: true },
      }),
    ]);

    const sum = (list: { amount: { toNumber(): number } }[]) => list.reduce((s, e) => s + e.amount.toNumber(), 0);
    const pct = (current: number, previousValue: number) =>
      previousValue > 0 ? ((current - previousValue) / previousValue) * 100 : null;

    const totalAmount = sum(expenses);
    const totalSalaries = sum(expenses.filter((e) => e.category === 'Salaires'));
    const totalMarket = sum(expenses.filter((e) => e.category === 'Marché'));
    const totalFixedCharges = totalAmount - totalSalaries - totalMarket;

    const previousTotalAmount = sum(previousExpenses);
    const previousTotalSalaries = sum(previousExpenses.filter((e) => e.category === 'Salaires'));
    const previousTotalMarket = sum(previousExpenses.filter((e) => e.category === 'Marché'));
    const previousTotalFixedCharges = previousTotalAmount - previousTotalSalaries - previousTotalMarket;

    const changePercent = pct(totalAmount, previousTotalAmount);
    const changePercentSalaries = pct(totalSalaries, previousTotalSalaries);
    const changePercentMarket = pct(totalMarket, previousTotalMarket);
    const changePercentFixedCharges = pct(totalFixedCharges, previousTotalFixedCharges);

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
      changePercentSalaries,
      changePercentMarket,
      changePercentFixedCharges,
      byCategory,
      recent: [...expenses]
        .sort((a, b) => b.expenseDate.getTime() - a.expenseDate.getTime())
        .slice(0, 8),
    };
  }

  private historyWhere(establishmentId: string, query: ExpenseHistoryQueryDto) {
    // `week` encode déjà l'année dans `weekOf` (une date ISO complète) — exiger
    // `year` en plus pour cette branche ferait échouer silencieusement le
    // filtrage de période dès que le client envoie period='week' sans année
    // (exactement le cas du test ci-dessus, qui ne passe pas `year`).
    const hasPeriod = query.period === 'week' ? true : Boolean(query.period && query.year);
    const range = hasPeriod
      ? resolveExpensePeriodRange({ period: query.period!, year: query.year!, month: query.month, weekOf: query.weekOf })
      : undefined;
    return {
      establishmentId,
      ...(range ? { expenseDate: { gte: range.from, lte: range.to } } : {}),
      ...(query.category ? { category: query.category } : {}),
      ...(query.status ? { status: query.status } : {}),
      ...(query.paymentMethod ? { paymentMethod: query.paymentMethod } : {}),
    };
  }

  async history(establishmentId: string, query: ExpenseHistoryQueryDto) {
    const where = this.historyWhere(establishmentId, query);
    const page = query.page && query.page > 0 ? query.page : 1;
    const pageSize = query.pageSize && query.pageSize > 0 ? query.pageSize : 8;
    const [items, total] = await Promise.all([
      this.prisma.expense.findMany({ where, orderBy: { expenseDate: 'desc' }, skip: (page - 1) * pageSize, take: pageSize }),
      this.prisma.expense.count({ where }),
    ]);
    return { items, total, page, pageSize };
  }

  /** Mêmes libellés français que `ExpensePaymentMethod`/`ExpenseStatus` côté Flutter (`expense_models.dart`) — l'export doit afficher exactement ce qui est montré à l'écran, pas les valeurs techniques brutes stockées en base. */
  private static readonly paymentMethodLabels: Record<string, string> = {
    cash: 'Espèces',
    mobile_money: 'Mobile Money',
    bank_transfer: 'Virement',
  };
  private static readonly statusLabels: Record<string, string> = {
    paid: 'Payée',
    pending: 'En attente',
    cancelled: 'Annulée',
  };

  /** Même pattern que ReportsService.beveragesSoldExcel — respecte les filtres actifs, jamais paginé (l'export contient tout ce qui correspond au filtre). */
  async exportHistoryExcel(establishmentId: string, query: ExpenseHistoryQueryDto): Promise<{ buffer: Buffer; filename: string }> {
    const where = this.historyWhere(establishmentId, query);
    const expenses = await this.prisma.expense.findMany({ where, orderBy: { expenseDate: 'desc' } });

    const workbook = new ExcelJS.Workbook();
    const sheet = workbook.addWorksheet('Historique des dépenses');
    sheet.columns = [
      { header: 'Date', key: 'date', width: 14 },
      { header: 'Libellé', key: 'label', width: 30 },
      { header: 'Nature', key: 'category', width: 18 },
      { header: 'Montant (FCFA)', key: 'amount', width: 18 },
      { header: 'Type', key: 'periodicity', width: 14 },
      { header: 'Mode de paiement', key: 'paymentMethod', width: 18 },
      { header: 'Statut', key: 'status', width: 14 },
    ];
    sheet.getRow(1).font = { bold: true };
    let total = 0;
    for (const e of expenses) {
      const amount = e.amount.toNumber();
      total += amount;
      sheet.addRow({
        date: e.expenseDate.toISOString().slice(0, 10),
        label: e.label,
        category: e.category ?? 'Autre',
        amount,
        periodicity: e.periodicity === 'recurring' ? 'Récurrente' : 'Ponctuelle',
        paymentMethod: ExpensesService.paymentMethodLabels[e.paymentMethod] ?? e.paymentMethod,
        status: ExpensesService.statusLabels[e.status] ?? e.status,
      });
    }
    const totalRow = sheet.addRow({ label: 'TOTAL', amount: total });
    totalRow.font = { bold: true };

    const buffer = (await workbook.xlsx.writeBuffer()) as ExcelJS.Buffer;
    const pad = (n: number) => String(n).padStart(2, '0');
    const now = new Date();
    const filename = `Historique depenses ${pad(now.getDate())}-${pad(now.getMonth() + 1)}-${now.getFullYear()}.xlsx`;
    return { buffer: Buffer.from(buffer), filename };
  }
}
