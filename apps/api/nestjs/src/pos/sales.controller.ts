import { Body, Controller, Get, Param, Post, Query, Req, UseGuards } from '@nestjs/common';
import type { Request } from 'express';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { CreateSaleDto } from './dto/create-sale.dto.js';
import { SalesService } from './sales.service.js';

@Controller('establishments/:establishmentId/sales')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
export class SalesController {
  constructor(private readonly sales: SalesService) {}

  @Post()
  @RequirePermissions('pos.sell')
  create(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Body() dto: CreateSaleDto) {
    return this.sales.create(establishmentId, request.user!.sub, dto);
  }

  @Get('last-order-number')
  @RequirePermissions('pos.sell')
  lastOrderNumber(@Param('establishmentId') establishmentId: string) {
    return this.sales.lastOrderNumber(establishmentId).then((orderNumber) => ({ orderNumber }));
  }

  @Get('last-market-number')
  @RequirePermissions('pos.sell')
  lastMarketNumber(@Param('establishmentId') establishmentId: string) {
    return this.sales.lastMarketNumber(establishmentId).then((marketNumber) => ({ marketNumber }));
  }

  @Get(':saleId')
  @RequirePermissions('pos.sell')
  get(@Param('establishmentId') establishmentId: string, @Param('saleId') saleId: string) {
    return this.sales.get(establishmentId, saleId);
  }

  @Get()
  @RequirePermissions('pos.sell')
  listForDay(@Param('establishmentId') establishmentId: string, @Query('day') day: string) {
    return this.sales.listForDay(establishmentId, day ?? new Date().toISOString().slice(0, 10));
  }

  @Post(':saleId/refund')
  @RequirePermissions('pos.refund')
  refund(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Param('saleId') saleId: string) {
    return this.sales.refund(establishmentId, request.user!.sub, saleId);
  }
}
