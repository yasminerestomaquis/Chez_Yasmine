import { Body, Controller, Param, Post, UseGuards } from '@nestjs/common';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { CreateReservationDto } from './dto/reservation-operations.dto.js';
import { ReservationsService } from './reservations.service.js';

@Controller('establishments/:establishmentId')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
@RequirePermissions('tables.manage')
export class ReservationsController {
  constructor(private readonly reservations: ReservationsService) {}

  @Post('tables/:tableId/reservations')
  create(
    @Param('establishmentId') establishmentId: string,
    @Param('tableId') tableId: string,
    @Body() dto: CreateReservationDto,
  ) {
    return this.reservations.create(establishmentId, tableId, dto);
  }

  @Post('reservations/:reservationId/cancel')
  cancel(@Param('establishmentId') establishmentId: string, @Param('reservationId') reservationId: string) {
    return this.reservations.cancel(establishmentId, reservationId);
  }
}
