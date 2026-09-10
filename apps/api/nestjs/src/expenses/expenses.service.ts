import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import { ActivityNotifierService } from '../notifications/activity-notifier.service.js';
import type { CreateExpenseDto, UpdateExpenseDto } from './dto/expense.dto.js';

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
}
