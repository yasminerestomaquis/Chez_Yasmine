import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import type { CreateReservationDto } from './dto/reservation-operations.dto.js';

/// Statuts possibles d'une réservation : 'pending' (active, en attente du
/// client) → 'seated' (le client est arrivé, consommée par l'ouverture de la
/// table) ou 'cancelled' (annulée manuellement). Jamais deux réservations
/// 'pending' actives à la fois pour une même table (la table passe elle-même
/// en statut 'reserved' pendant ce temps, ce qui empêche d'en créer une autre).
@Injectable()
export class ReservationsService {
  constructor(private readonly prisma: PrismaService) {}

  async create(establishmentId: string, tableId: string, dto: CreateReservationDto) {
    const table = await this.prisma.restaurantTable.findFirst({ where: { id: tableId, establishmentId } });
    if (!table) {
      throw new NotFoundException('Table introuvable pour cet établissement');
    }
    if (table.status !== 'free') {
      throw new ConflictException('Seule une table libre peut être réservée');
    }

    return this.prisma.$transaction(async (tx) => {
      const reservation = await tx.reservation.create({
        data: {
          tableId,
          customerName: dto.customerName,
          phone: dto.phone,
          reservedAt: new Date(dto.reservedAt),
          status: 'pending',
        },
      });
      await tx.restaurantTable.update({ where: { id: tableId }, data: { status: 'reserved' } });
      return reservation;
    });
  }

  async cancel(establishmentId: string, reservationId: string) {
    const reservation = await this.prisma.reservation.findFirst({
      where: { id: reservationId, table: { establishmentId } },
      include: { table: true },
    });
    if (!reservation) {
      throw new NotFoundException('Réservation introuvable pour cet établissement');
    }
    if (reservation.status !== 'pending') {
      throw new BadRequestException('Cette réservation a déjà été traitée');
    }

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.reservation.update({ where: { id: reservationId }, data: { status: 'cancelled' } });
      // Ne libère la table que si elle est toujours au statut 'reserved' posé
      // par cette réservation — une table déjà ouverte entre-temps (openTable
      // a déjà consommé la réservation) ne doit pas être touchée ici.
      if (reservation.table.status === 'reserved') {
        await tx.restaurantTable.update({ where: { id: reservation.tableId }, data: { status: 'free' } });
      }
      return updated;
    });
  }
}
