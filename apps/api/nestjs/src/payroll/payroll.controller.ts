import { Body, Controller, Get, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import type { Request } from 'express';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { PreparePayrollRunDto, UpdatePayrollLineDto } from './dto/payroll.dto.js';
import { PayrollService } from './payroll.service.js';

@Controller('establishments/:establishmentId/payroll')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
export class PayrollController {
  constructor(private readonly payroll: PayrollService) {}

  @Get('runs')
  @RequirePermissions('payroll.view')
  list(@Param('establishmentId') establishmentId: string) {
    return this.payroll.list(establishmentId);
  }

  @Get('dashboard')
  @RequirePermissions('payroll.view')
  dashboard(
    @Param('establishmentId') establishmentId: string,
    @Query('year') year: string,
    @Query('month') month: string,
  ) {
    return this.payroll.dashboard(establishmentId, Number(year), Number(month));
  }

  @Post('runs')
  @RequirePermissions('payroll.manage')
  prepare(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Body() dto: PreparePayrollRunDto) {
    return this.payroll.prepare(establishmentId, request.user!.sub, dto);
  }

  @Patch('runs/:runId/lines/:lineId')
  @RequirePermissions('payroll.manage')
  updateLine(
    @Param('establishmentId') establishmentId: string,
    @Param('runId') runId: string,
    @Param('lineId') lineId: string,
    @Body() dto: UpdatePayrollLineDto,
  ) {
    return this.payroll.updateLine(establishmentId, runId, lineId, dto);
  }

  @Post('runs/:runId/validate')
  @RequirePermissions('payroll.manage')
  validate(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Param('runId') runId: string) {
    return this.payroll.validate(establishmentId, runId, request.user!.sub);
  }

  @Post('runs/:runId/pay')
  @RequirePermissions('payroll.manage')
  pay(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Param('runId') runId: string) {
    return this.payroll.pay(establishmentId, runId, request.user!.sub);
  }

  @Post('runs/:runId/cancel')
  @RequirePermissions('payroll.manage')
  cancel(@Param('establishmentId') establishmentId: string, @Param('runId') runId: string) {
    return this.payroll.cancel(establishmentId, runId);
  }
}
