import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import { ActivityNotifierService } from '../notifications/activity-notifier.service.js';
import type { PreparePayrollRunDto, UpdatePayrollLineDto } from './dto/payroll.dto.js';

@Injectable()
export class PayrollService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly activityNotifier: ActivityNotifierService,
  ) {}

  list(establishmentId: string) {
    return this.prisma.payrollRun.findMany({
      where: { establishmentId },
      include: { lines: { include: { employee: { select: { id: true, lastName: true, firstName: true } } } } },
      orderBy: { periodStart: 'desc' },
    });
  }

  /** Une ligne par employé actif au moment de la préparation, `baseSalary` figé sur `Employee.weeklySalary` (un changement de salaire ultérieur ne réécrit jamais un bulletin déjà préparé). */
  async prepare(establishmentId: string, userId: string, dto: PreparePayrollRunDto) {
    const employees = await this.prisma.employee.findMany({
      where: { establishmentId, status: 'active' },
      select: { id: true, weeklySalary: true },
    });
    const run = await this.prisma.payrollRun.create({
      data: {
        establishmentId,
        periodStart: new Date(dto.periodStart),
        periodEnd: new Date(dto.periodEnd),
        status: 'prepared',
        preparedBy: userId,
        lines: {
          create: employees.map((e) => {
            const baseSalary = e.weeklySalary.toNumber();
            return { employeeId: e.id, baseSalary, advance: 0, adjustment: 0, netAmount: baseSalary };
          }),
        },
      },
      include: { lines: true },
    });
    return run;
  }

  private async getEditableLine(establishmentId: string, payrollRunId: string, lineId: string) {
    const line = await this.prisma.payrollLine.findFirst({
      where: { id: lineId, payrollRunId },
      include: { payrollRun: true },
    });
    if (!line || line.payrollRun.establishmentId !== establishmentId) {
      throw new NotFoundException('Ligne de paie introuvable pour cet établissement');
    }
    if (line.payrollRun.status !== 'prepared') {
      throw new BadRequestException('Cette paie n\'est plus modifiable (déjà validée, payée ou annulée)');
    }
    return line;
  }

  async updateLine(establishmentId: string, payrollRunId: string, lineId: string, dto: UpdatePayrollLineDto) {
    const line = await this.getEditableLine(establishmentId, payrollRunId, lineId);
    const netAmount = line.baseSalary.toNumber() - dto.advance + dto.adjustment;
    await this.prisma.payrollLine.update({
      where: { id: lineId },
      data: { advance: dto.advance, adjustment: dto.adjustment, netAmount },
    });
  }

  private async getRun(establishmentId: string, payrollRunId: string) {
    const run = await this.prisma.payrollRun.findFirst({
      where: { id: payrollRunId, establishmentId },
      include: { lines: true },
    });
    if (!run) {
      throw new NotFoundException('Paie introuvable pour cet établissement');
    }
    return run;
  }

  async validate(establishmentId: string, payrollRunId: string, userId: string) {
    const run = await this.getRun(establishmentId, payrollRunId);
    if (run.status !== 'prepared') {
      throw new BadRequestException('Seule une paie "préparée" peut être validée');
    }
    await this.prisma.payrollRun.update({
      where: { id: payrollRunId },
      data: { status: 'validated', validatedBy: userId, validatedAt: new Date() },
    });
  }

  /**
   * Crée UNE dépense de nature "Salaires" pour l'ensemble de la paie, jamais
   * deux fois : (1) le contrôle `status !== 'validated'` bloque un second
   * appel une fois `status` passé à 'paid' ; (2) `Expense.payrollRunId`
   * porte une contrainte @unique en base — même en cas de double requête
   * concurrente, la seconde échouerait au niveau SQL plutôt que de dupliquer
   * la dépense (défense en profondeur, voir docs/api/expenses.md).
   */
  async pay(establishmentId: string, payrollRunId: string, userId: string) {
    const run = await this.getRun(establishmentId, payrollRunId);
    if (run.status !== 'validated') {
      throw new BadRequestException('Seule une paie "validée" peut être payée');
    }
    const total = run.lines.reduce((sum, l) => sum + l.netAmount.toNumber(), 0);
    const paidAt = new Date();

    await this.prisma.$transaction([
      this.prisma.payrollRun.update({
        where: { id: payrollRunId },
        data: { status: 'paid', paidBy: userId, paidAt },
      }),
      this.prisma.expense.create({
        data: {
          establishmentId,
          label: 'Paiement des salaires',
          category: 'Salaires',
          amount: total,
          expenseDate: run.periodEnd,
          periodicity: 'recurring',
          paymentMethod: 'cash',
          status: 'paid',
          payrollRunId,
        },
      }),
    ]);

    await this.activityNotifier.notify(
      establishmentId,
      'Salaires payés',
      `${total.toLocaleString('fr-FR')} FCFA versés pour ${run.lines.length} employé(s)`,
    );
  }

  async cancel(establishmentId: string, payrollRunId: string) {
    const run = await this.getRun(establishmentId, payrollRunId);
    if (run.status === 'paid') {
      throw new BadRequestException('Une paie déjà payée ne peut plus être annulée');
    }
    if (run.status === 'cancelled') {
      throw new BadRequestException('Cette paie est déjà annulée');
    }
    await this.prisma.payrollRun.update({
      where: { id: payrollRunId },
      data: { status: 'cancelled', cancelledAt: new Date() },
    });
  }

  /** Tableau de bord Salaires — voir docs/api/expenses.md. `year`/`month` en 1-12. */
  async dashboard(establishmentId: string, year: number, month: number) {
    const from = new Date(year, month - 1, 1);
    const to = new Date(year, month, 0, 23, 59, 59, 999);
    const [employeeCount, runs] = await Promise.all([
      this.prisma.employee.count({ where: { establishmentId, status: 'active' } }),
      this.prisma.payrollRun.findMany({
        where: { establishmentId, periodStart: { gte: from, lte: to }, status: { not: 'cancelled' } },
        include: { lines: true },
      }),
    ]);
    let massSalariale = 0;
    let totalPaid = 0;
    for (const run of runs) {
      const runTotal = run.lines.reduce((sum, l) => sum + l.netAmount.toNumber(), 0);
      massSalariale += runTotal;
      if (run.status === 'paid') totalPaid += runTotal;
    }
    return { employeeCount, massSalariale, totalPaid, remaining: massSalariale - totalPaid };
  }
}
