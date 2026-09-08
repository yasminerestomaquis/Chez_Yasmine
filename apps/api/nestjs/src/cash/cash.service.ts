import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import { ActivityNotifierService } from '../notifications/activity-notifier.service.js';
import type { CreateCashClosingDto } from './dto/create-cash-closing.dto.js';

@Injectable()
export class CashService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly activityNotifier: ActivityNotifierService,
  ) {}

  /**
   * PointOfSale/CashRegister exist in the schema (Phase 3) but no module
   * manages them yet, and this app has no multi-register UI — building one
   * now, before any establishment actually needs more than one register,
   * would be scope creep. A single default register is created lazily on
   * first closing instead; multi-register support can be layered on later
   * without changing this method's contract.
   */
  private async getOrCreateDefaultRegister(establishmentId: string) {
    const pointOfSale = await this.prisma.pointOfSale.findFirst({
      where: { establishmentId },
      include: { cashRegisters: true },
    });
    if (pointOfSale?.cashRegisters[0]) {
      return pointOfSale.cashRegisters[0];
    }
    const pos = pointOfSale ?? (await this.prisma.pointOfSale.create({ data: { establishmentId, name: 'Caisse principale' } }));
    return this.prisma.cashRegister.create({ data: { pointOfSaleId: pos.id, name: 'Caisse' } });
  }

  /**
   * Expected cash = cash sale payments minus cash expenses recorded over the
   * counted period. Expenses are assumed paid out of the till in cash — this
   * app has no payment-method field on Expense, and for a maquis-bar that
   * assumption holds in practice; revisit if that stops being true.
   */
  async close(establishmentId: string, userId: string, dto: CreateCashClosingDto) {
    const register = await this.getOrCreateDefaultRegister(establishmentId);
    const openedAt = new Date(dto.openedAt);
    const closedAt = new Date();

    const [cashPayments, cashExpenses] = await Promise.all([
      this.prisma.payment.aggregate({
        _sum: { amount: true },
        where: { method: 'cash', sale: { establishmentId, voidedAt: null, createdAt: { gte: openedAt, lte: closedAt } } },
      }),
      this.prisma.expense.aggregate({
        _sum: { amount: true },
        where: { establishmentId, expenseDate: { gte: openedAt, lte: closedAt } },
      }),
    ]);

    const expectedAmount = (cashPayments._sum.amount?.toNumber() ?? 0) - (cashExpenses._sum.amount?.toNumber() ?? 0);

    const closing = await this.prisma.cashClosing.create({
      data: {
        cashRegisterId: register.id,
        openedAt,
        closedAt,
        expectedAmount,
        countedAmount: dto.countedAmount,
        closedBy: userId,
      },
    });

    const difference = dto.countedAmount - expectedAmount;
    await this.activityNotifier.notify(
      establishmentId,
      'Clôture de caisse',
      `Montant compté : ${dto.countedAmount.toLocaleString('fr-FR')} FCFA — écart : ${difference.toLocaleString('fr-FR')} FCFA`,
    );
    return { ...closing, difference };
  }

  async list(establishmentId: string) {
    const closings = await this.prisma.cashClosing.findMany({
      where: { cashRegister: { pointOfSale: { establishmentId } } },
      orderBy: { closedAt: 'desc' },
    });
    return closings.map((closing) => ({
      ...closing,
      difference: closing.countedAmount.toNumber() - closing.expectedAmount.toNumber(),
    }));
  }
}
