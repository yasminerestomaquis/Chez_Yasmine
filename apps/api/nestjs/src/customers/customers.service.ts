import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import type { CreateCustomerDto, UpdateCustomerDto } from './dto/customer.dto.js';

@Injectable()
export class CustomersService {
  constructor(private readonly prisma: PrismaService) {}

  list(establishmentId: string) {
    return this.prisma.customer.findMany({ where: { establishmentId }, orderBy: { name: 'asc' } });
  }

  async get(establishmentId: string, customerId: string) {
    const customer = await this.prisma.customer.findFirst({ where: { id: customerId, establishmentId } });
    if (!customer) {
      throw new NotFoundException('Client introuvable pour cet établissement');
    }
    return customer;
  }

  create(establishmentId: string, dto: CreateCustomerDto) {
    return this.prisma.customer.create({
      data: { establishmentId, name: dto.name, phone: dto.phone, address: dto.address, creditLimit: dto.creditLimit ?? 0 },
    });
  }

  async update(establishmentId: string, customerId: string, dto: UpdateCustomerDto) {
    const { count } = await this.prisma.customer.updateMany({ where: { id: customerId, establishmentId }, data: dto });
    if (count === 0) {
      throw new NotFoundException('Client introuvable pour cet établissement');
    }
    return this.prisma.customer.findUniqueOrThrow({ where: { id: customerId } });
  }

  async remove(establishmentId: string, customerId: string): Promise<void> {
    const { count } = await this.prisma.customer.deleteMany({ where: { id: customerId, establishmentId } });
    if (count === 0) {
      throw new NotFoundException('Client introuvable pour cet établissement');
    }
  }
}
