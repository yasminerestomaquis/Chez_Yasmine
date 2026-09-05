import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import type { CreateExpenseDto, UpdateExpenseDto } from './dto/expense.dto.js';

@Injectable()
export class ExpensesService {
  constructor(private readonly prisma: PrismaService) {}

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

  create(establishmentId: string, dto: CreateExpenseDto) {
    return this.prisma.expense.create({
      data: {
        establishmentId,
        label: dto.label,
        category: dto.category,
        amount: dto.amount,
        expenseDate: dto.expenseDate ? new Date(dto.expenseDate) : undefined,
        note: dto.note,
      },
    });
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
