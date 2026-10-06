import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import { ActivityNotifierService } from '../notifications/activity-notifier.service.js';
import type {
  AddPayrollLineDto,
  PreparePayrollRunDto,
  UpdatePayrollLineDto,
  UpdatePayrollRunDto,
} from './dto/payroll.dto.js';

const DATE_ONLY = /^\d{4}-\d{2}-\d{2}$/;

function parseDateFilter(value: string | undefined, name: string): Date | undefined {
  if (!value) return undefined;
  const date = DATE_ONLY.test(value) ? new Date(value) : null;
  if (!date || Number.isNaN(date.getTime())) {
    throw new BadRequestException(`Paramètre « ${name} » invalide : format AAAA-MM-JJ attendu`);
  }
  return date;
}

@Injectable()
export class PayrollService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly activityNotifier: ActivityNotifierService,
  ) {}

  /**
   * `from` / `to` (AAAA-MM-JJ, optionnels) : ne garde que les paies dont la
   * période CHEVAUCHE [from, to] (fin de période >= from ET début <= to) —
   * historique des paies sur une période choisie par l'utilisateur.
   */
  list(establishmentId: string, from?: string, to?: string) {
    const fromDate = parseDateFilter(from, 'from');
    const toDate = parseDateFilter(to, 'to');
    if (fromDate && toDate && toDate.getTime() < fromDate.getTime()) {
      throw new BadRequestException('La fin de la période ne peut pas précéder le début');
    }
    return this.prisma.payrollRun.findMany({
      where: {
        establishmentId,
        ...(fromDate ? { periodEnd: { gte: fromDate } } : {}),
        ...(toDate ? { periodStart: { lte: toDate } } : {}),
      },
      // `expense` : la dépense « Salaires » générée au paiement (null tant que la
      // paie n'est pas payée) — l'historique des paies affiche sa date de saisie.
      include: {
        lines: { include: { employee: { select: { id: true, lastName: true, firstName: true } } } },
        expense: { select: { id: true, amount: true, expenseDate: true, createdAt: true } },
      },
      orderBy: [{ periodStart: 'desc' }, { createdAt: 'desc' }],
    });
  }

  /**
   * Une ligne par employé actif au moment de la préparation, `baseSalary` figé
   * sur `Employee.weeklySalary` (un changement de salaire ultérieur ne réécrit
   * jamais un bulletin déjà préparé).
   *
   * `periodType` ('weekly' par défaut, 'monthly') : une paie hebdomadaire ne
   * reprend que les employés payés à la semaine, une paie mensuelle que ceux
   * payés au mois. Une seule paie non annulée par type et par début de période
   * (évite le doublon quand on prépare une semaine omise après coup).
   */
  async prepare(establishmentId: string, userId: string, dto: PreparePayrollRunDto) {
    const periodType = dto.periodType ?? 'weekly';
    const duplicate = await this.prisma.payrollRun.findFirst({
      where: { establishmentId, periodType, periodStart: new Date(dto.periodStart), status: { not: 'cancelled' } },
      select: { id: true },
    });
    if (duplicate) {
      throw new BadRequestException('Une paie existe déjà pour cette période (annulez-la d\'abord pour la refaire)');
    }
    const employees = await this.prisma.employee.findMany({
      where: { establishmentId, status: 'active', salaryType: periodType },
      select: { id: true, weeklySalary: true },
    });
    const run = await this.prisma.payrollRun.create({
      data: {
        establishmentId,
        periodStart: new Date(dto.periodStart),
        periodEnd: new Date(dto.periodEnd),
        periodType,
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

  /**
   * Paie déjà payée : la dépense « Salaires » générée au paiement doit suivre
   * le nouveau total, dans la même transaction que la modification des lignes.
   */
  private async syncPaidExpenseTotal(
    tx: Pick<PrismaService, 'payrollLine' | 'expense'>,
    payrollRunId: string,
  ) {
    const lines = await tx.payrollLine.findMany({ where: { payrollRunId }, select: { netAmount: true } });
    const total = lines.reduce((sum, l) => sum + l.netAmount.toNumber(), 0);
    await tx.expense.update({ where: { payrollRunId }, data: { amount: total } });
  }

  /**
   * Ajoute un employé sur une paie non annulée (préparée, validée ou payée) :
   * ligne au salaire hebdomadaire courant, sans avance ni ajustement. Un seul
   * bulletin par employé et par paie (@@unique en base, contrôlé ici pour un
   * message clair).
   */
  async addLine(establishmentId: string, payrollRunId: string, dto: AddPayrollLineDto) {
    const run = await this.getRun(establishmentId, payrollRunId);
    if (run.status === 'cancelled') {
      throw new BadRequestException('Cette paie est annulée : elle n\'est plus modifiable');
    }
    const employee = await this.prisma.employee.findFirst({
      where: { id: dto.employeeId, establishmentId },
      select: { id: true, status: true, weeklySalary: true, salaryType: true },
    });
    if (!employee) {
      throw new NotFoundException('Employé introuvable pour cet établissement');
    }
    if (employee.salaryType !== run.periodType) {
      throw new BadRequestException(
        run.periodType === 'monthly'
          ? 'Cet employé est payé à la semaine : il ne peut pas figurer sur une paie mensuelle'
          : 'Cet employé est payé au mois : il ne peut pas figurer sur une paie hebdomadaire',
      );
    }
    if (employee.status !== 'active') {
      throw new BadRequestException('Seul un employé actif peut être ajouté à une paie');
    }
    if (run.lines.some((l) => l.employeeId === dto.employeeId)) {
      throw new BadRequestException('Cet employé figure déjà sur cette paie');
    }
    const baseSalary = employee.weeklySalary.toNumber();
    const data = { payrollRunId, employeeId: employee.id, baseSalary, advance: 0, adjustment: 0, netAmount: baseSalary };
    if (run.status !== 'paid') {
      await this.prisma.payrollLine.create({ data });
      return;
    }
    await this.prisma.$transaction(async (tx) => {
      await tx.payrollLine.create({ data });
      await this.syncPaidExpenseTotal(tx, payrollRunId);
    });
  }

  /** Retire un employé d'une paie non annulée ; une paie payée voit sa dépense « Salaires » ajustée. */
  async removeLine(establishmentId: string, payrollRunId: string, lineId: string) {
    const line = await this.getEditableLine(establishmentId, payrollRunId, lineId);
    if (line.payrollRun.status !== 'paid') {
      await this.prisma.payrollLine.delete({ where: { id: lineId } });
      return;
    }
    await this.prisma.$transaction(async (tx) => {
      await tx.payrollLine.delete({ where: { id: lineId } });
      await this.syncPaidExpenseTotal(tx, payrollRunId);
    });
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
      await this.syncPaidExpenseTotal(tx, payrollRunId);
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
