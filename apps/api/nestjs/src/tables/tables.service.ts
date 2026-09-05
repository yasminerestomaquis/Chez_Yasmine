import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import type { CreateTableDto } from './dto/create-table.dto.js';
import type { UpdateTableDto } from './dto/update-table.dto.js';

@Injectable()
export class TablesService {
  constructor(private readonly prisma: PrismaService) {}

  list(establishmentId: string) {
    return this.prisma.restaurantTable.findMany({ where: { establishmentId }, orderBy: [{ zone: 'asc' }, { name: 'asc' }] });
  }

  create(establishmentId: string, dto: CreateTableDto) {
    return this.prisma.restaurantTable.create({ data: { establishmentId, name: dto.name, zone: dto.zone } });
  }

  async update(establishmentId: string, tableId: string, dto: UpdateTableDto) {
    const { count } = await this.prisma.restaurantTable.updateMany({ where: { id: tableId, establishmentId }, data: dto });
    if (count === 0) {
      throw new NotFoundException('Table introuvable pour cet établissement');
    }
    return this.prisma.restaurantTable.findUniqueOrThrow({ where: { id: tableId } });
  }

  async remove(establishmentId: string, tableId: string): Promise<void> {
    const { count } = await this.prisma.restaurantTable.deleteMany({ where: { id: tableId, establishmentId } });
    if (count === 0) {
      throw new NotFoundException('Table introuvable pour cet établissement');
    }
  }
}
