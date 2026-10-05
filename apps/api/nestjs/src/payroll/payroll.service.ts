import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import { ActivityNotifierService } from '../notifications/activity-notifier.service.js';
import type { PreparePayrollRunDto, UpdatePayrollLineDto, UpdatePayrollRunDto } from './dto/payroll.dto.js';

@Injectable()
export class PayrollService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly activityNotifier: ActivityNotifierService,
  ) {}

  list(establishmentId: string) {
    return this.prisma.payrollRun.findMany({
      where: { establishmentId },
      // `expense` : la dépense « Salaires » générée au paiement (null tant que la
      // paie n'est pas payée) — l'historique des paies affiche sa date de saisie.
      include: {
        lines: { include: { employee: { select: { id: true, lastName: true, firstName: true } } } },
        expense: { select: { id: true, amount: true, expenseDate: true, createdAt: true } },
      },
      orderBy: [{ periodStart: 'desc' }, { createdAt: 'desc' }],
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
      // `include: { lines: { include: { employee } } }`, pas juste `lines:
      // true` : la réponse est désérialisée côté Flutter en `PayrollRun`
      // (lib/payroll/payroll_models.dart), dont `PayrollLine.fromJson` lit
      // `json['employee'].lastName/firstName` sans garde — un `employee`
      // absent ferait planter l'écran juste après "Préparer la paie". Même
      // forme que `list()` ci-dessus, pour que les deux réponses aient
      // exactement la même shape côté client.
      include: { lines: { include: { employee: { select: { id: true, lastName: true, firstName: true } } } } },
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
    // Historique des paies (demande du 2026-10-05) : une paie préparée, validée
    // OU déjà payée reste corrigeable ; seule une paie annulée est figée.
    if (line.payrollRun.status === 'cancelled') {
      throw new BadRequestException('Cette paie est annulée : elle n\'est plus modifiable');
    }
    return line;
  }

  async updateLine(establishmentId: string, payrollRunId: string, lineId: string, dto: UpdatePayrollLineDto) {
    const line = await this.getEditableLine(establishmentId, payrollRunId, lineId);
    const netAmount = line.baseSalary.toNumber() - dto.advance + dto.adjustment;
    const data = { advance: dto.advance, adjustment: dto.adjustment, netAmount };
    if (line.payrollRun.status !== 'paid') {
      await this.prisma.payrollLine.update({ where: { id: lineId }, data });
      return;
    }
    // Paie déjà payée : la dépense « Salaires » générée au paiement doit suivre
    // le nouveau total, dans la même transaction — sinon les totaux de l'onglet
    // Dépenses (Vue d'ensemble, Historique) divergeraient de la paie.
    await this.prisma.$transaction(async (tx) => {
      await tx.payrollLine.update({ where: { id: lineId }, data });
      const lines = await tx.payrollLine.findMany({ where: { payrollRunId }, select: { netAmount: true } });
      const total = lines.reduce((sum, l) => sum + l.netAmount.toNumber(), 0);
      await tx.expense.update({ where: { payrollRunId }, data: { amount: total } });
    });
  }

  /**
   * Corrige la période d'une paie (« Du … au … »). Pour une paie déjà payée, la
   * date de la dépense « Salaires » liée suit la fin de période (c'est la règle
   * posée par `pay()`), dans la même transaction.
   */
  async updateRun(establishmentId: string, payrollRunId: string, dto: UpdatePayrollRunDto) {
    const run = await this.getRun(establishmentId, payrollRunId);
    if (run.status === 'cancelled') {
      throw new BadRequestException('Cette paie est annulée : elle n\'est plus modifiable');
    }
    const periodStart = dto.periodStart ? new Date(dto.periodStart) : run.periodStart;
    const periodEnd = dto.periodEnd ? new Date(dto.periodEnd) : run.periodEnd;
    if (periodEnd.getTime() < periodStart.getTime()) {
      throw new BadRequestException('La fin de période ne peut pas précéder le début');
    }
    const update = this.prisma.payrollRun.update({
      where: { id: payrollRunId },
      data: { periodStart, periodEnd },
    });
    if (run.status !== 'paid') {
      await update;
      return;
    }
    await this.prisma.$transaction([
      update,
      this.prisma.expense.update({ where: { payrollRunId }, data: { expenseDate: periodEnd } }),
    ]);
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
      userId,
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
