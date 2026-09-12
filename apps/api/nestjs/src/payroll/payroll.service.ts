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
}
