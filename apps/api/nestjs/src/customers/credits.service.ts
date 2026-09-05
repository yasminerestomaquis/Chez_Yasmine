import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { applyRepayment } from '../pos/credit-math.js';
import { PrismaService } from '../prisma/prisma.service.js';
import type { CreateCreditPaymentDto } from './dto/customer.dto.js';

export interface CreditHistoryEntry {
  type: 'credit' | 'repayment';
  amount: number;
  saleId?: string;
  createdAt: Date;
}

@Injectable()
export class CreditsService {
  constructor(private readonly prisma: PrismaService) {}

  private async getCustomerOrThrow(establishmentId: string, customerId: string) {
    const customer = await this.prisma.customer.findFirst({ where: { id: customerId, establishmentId } });
    if (!customer) {
      throw new NotFoundException('Client introuvable pour cet établissement');
    }
    return customer;
  }

  async history(establishmentId: string, customerId: string): Promise<CreditHistoryEntry[]> {
    await this.getCustomerOrThrow(establishmentId, customerId);
    const [credits, repayments] = await Promise.all([
      this.prisma.credit.findMany({ where: { customerId } }),
      this.prisma.creditPayment.findMany({ where: { customerId } }),
    ]);

    const entries: CreditHistoryEntry[] = [
      ...credits.map((c) => ({
        type: 'credit' as const,
        amount: c.amount.toNumber(),
        saleId: c.saleId ?? undefined,
        createdAt: c.createdAt,
      })),
      ...repayments.map((r) => ({ type: 'repayment' as const, amount: r.amount.toNumber(), createdAt: r.createdAt })),
    ];
    return entries.sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());
  }

  /** A voluntary repayment by the customer — strict about not overpaying, unlike the clamped reversal in SalesService.refund. */
  async recordRepayment(establishmentId: string, customerId: string, dto: CreateCreditPaymentDto) {
    const customer = await this.getCustomerOrThrow(establishmentId, customerId);

    let nextBalance: number;
    try {
      nextBalance = applyRepayment(customer.creditBalance.toNumber(), dto.amount);
    } catch (error) {
      throw new BadRequestException(error instanceof Error ? error.message : 'Remboursement invalide');
    }

    const [, payment] = await this.prisma.$transaction([
      this.prisma.customer.update({ where: { id: customerId }, data: { creditBalance: nextBalance } }),
      this.prisma.creditPayment.create({ data: { customerId, amount: dto.amount } }),
    ]);
    return payment;
  }
}
