import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { CreditsService } from './credits.service.js';
import { CreateCreditPaymentDto } from './dto/customer.dto.js';

@Controller('establishments/:establishmentId/customers/:customerId/credit')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
@RequirePermissions('credits.manage')
export class CreditsController {
  constructor(private readonly credits: CreditsService) {}

  @Get('history')
  history(@Param('establishmentId') establishmentId: string, @Param('customerId') customerId: string) {
    return this.credits.history(establishmentId, customerId);
  }

  @Post('payments')
  recordRepayment(
    @Param('establishmentId') establishmentId: string,
    @Param('customerId') customerId: string,
    @Body() dto: CreateCreditPaymentDto,
  ) {
    return this.credits.recordRepayment(establishmentId, customerId, dto);
  }
}
