import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import type { CreateSupplierDto, UpdateSupplierDto } from './dto/supplier.dto.js';

@Injectable()
export class SuppliersService {
  constructor(private readonly prisma: PrismaService) {}

  list(establishmentId: string) {
    return this.prisma.supplier.findMany({ where: { establishmentId }, orderBy: { name: 'asc' } });
  }

  create(establishmentId: string, dto: CreateSupplierDto) {
    return this.prisma.supplier.create({ data: { establishmentId, ...dto } });
  }

  async update(establishmentId: string, supplierId: string, dto: UpdateSupplierDto) {
    const { count } = await this.prisma.supplier.updateMany({ where: { id: supplierId, establishmentId }, data: dto });
    if (count === 0) {
      throw new NotFoundException('Fournisseur introuvable pour cet établissement');
    }
    return this.prisma.supplier.findUniqueOrThrow({ where: { id: supplierId } });
  }

  async remove(establishmentId: string, supplierId: string): Promise<void> {
    const { count } = await this.prisma.supplier.deleteMany({ where: { id: supplierId, establishmentId } });
    if (count === 0) {
      throw new NotFoundException('Fournisseur introuvable pour cet établissement');
    }
  }
}
