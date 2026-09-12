import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import type { CreateEmployeeDto, UpdateEmployeeDto } from './dto/employee.dto.js';

@Injectable()
export class EmployeesService {
  constructor(private readonly prisma: PrismaService) {}

  list(establishmentId: string) {
    return this.prisma.employee.findMany({
      where: { establishmentId },
      orderBy: { lastName: 'asc' },
    });
  }

  async create(establishmentId: string, dto: CreateEmployeeDto) {
    return this.prisma.employee.create({
      data: {
        establishmentId,
        lastName: dto.lastName,
        firstName: dto.firstName,
        gender: dto.gender,
        birthDate: dto.birthDate ? new Date(dto.birthDate) : undefined,
        phone: dto.phone,
        address: dto.address,
        position: dto.position,
        hireDate: new Date(dto.hireDate),
        contractType: dto.contractType,
        weeklySalary: dto.weeklySalary,
        team: dto.team,
        registrationNumber: dto.registrationNumber,
        notes: dto.notes,
        status: 'active',
      },
    });
  }

  /** Désactivation via `status: 'inactive'`, jamais de suppression : un employé peut être référencé par des PayrollLine passées (onDelete: Restrict), et son historique de paie doit rester consultable. */
  async update(establishmentId: string, employeeId: string, dto: UpdateEmployeeDto) {
    const { count } = await this.prisma.employee.updateMany({
      where: { id: employeeId, establishmentId },
      data: {
        lastName: dto.lastName,
        firstName: dto.firstName,
        gender: dto.gender,
        birthDate: dto.birthDate ? new Date(dto.birthDate) : undefined,
        phone: dto.phone,
        address: dto.address,
        position: dto.position,
        hireDate: dto.hireDate ? new Date(dto.hireDate) : undefined,
        contractType: dto.contractType,
        weeklySalary: dto.weeklySalary,
        team: dto.team,
        registrationNumber: dto.registrationNumber,
        notes: dto.notes,
        status: dto.status,
      },
    });
    if (count === 0) {
      throw new NotFoundException('Employé introuvable pour cet établissement');
    }
    return this.prisma.employee.findUniqueOrThrow({ where: { id: employeeId } });
  }
}
