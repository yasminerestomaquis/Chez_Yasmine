import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import type { CreateTableDto } from './dto/create-table.dto.js';
import type { UpdateTableDto } from './dto/update-table.dto.js';

@Injectable()
export class TablesService {
  constructor(private readonly prisma: PrismaService) {}

  async list(establishmentId: string) {
    const tables = await this.prisma.restaurantTable.findMany({
      where: { establishmentId },
      orderBy: [{ zone: 'asc' }, { name: 'asc' }],
      include: {
        // Toutes les additions ouvertes (pas juste la première — une table
        // peut en avoir plusieurs simultanément, voir docs/api/tables.md).
        orders: { where: { status: 'open' }, orderBy: { openedAt: 'asc' }, include: { items: true } },
        reservations: { where: { status: 'pending' }, orderBy: { reservedAt: 'asc' }, take: 1 },
      },
    });
    return tables.map((table) => {
      const orders = table.orders;
      const currentTotal =
        orders.length > 0
          ? orders.reduce(
              (sum, order) => sum + order.items.reduce((s, item) => s + Number(item.quantity) * Number(item.unitPrice), 0),
              0,
            )
          : null;
      // Le nombre de convives n'a pas vocation à se sommer entre plusieurs
      // additions — celui de la première addition ouverte (la plus ancienne).
      const guestCount = orders[0]?.guestCount ?? null;
      const reservation = table.reservations[0];
      return {
        id: table.id,
        establishmentId: table.establishmentId,
        name: table.name,
        zone: table.zone,
        status: table.status,
        createdAt: table.createdAt,
        guestCount,
        currentTotal,
        openOrderCount: orders.length,
        reservation: reservation
          ? {
              id: reservation.id,
              customerName: reservation.customerName,
              phone: reservation.phone,
              reservedAt: reservation.reservedAt,
            }
          : null,
      };
    });
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
