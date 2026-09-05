import { Body, Controller, Get, Param, Post, Req, UseGuards } from '@nestjs/common';
import type { Request } from 'express';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { CashService } from './cash.service.js';
import { CreateCashClosingDto } from './dto/create-cash-closing.dto.js';

@Controller('establishments/:establishmentId/cash/closings')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
@RequirePermissions('cash.manage')
export class CashController {
  constructor(private readonly cash: CashService) {}

  @Get()
  list(@Param('establishmentId') establishmentId: string) {
    return this.cash.list(establishmentId);
  }

  @Post()
  close(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Body() dto: CreateCashClosingDto) {
    return this.cash.close(establishmentId, request.user!.sub, dto);
  }
}
