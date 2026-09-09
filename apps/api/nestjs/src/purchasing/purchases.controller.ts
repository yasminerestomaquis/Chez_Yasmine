import { Body, Controller, Delete, Get, HttpCode, HttpStatus, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import type { Request } from 'express';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { CreatePurchaseDto } from './dto/create-purchase.dto.js';
import { UpdatePurchaseDto } from './dto/update-purchase.dto.js';
import { PurchasesService } from './purchases.service.js';

@Controller('establishments/:establishmentId/purchases')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
@RequirePermissions('purchases.manage')
export class PurchasesController {
  constructor(private readonly purchases: PurchasesService) {}

  @Get()
  list(@Param('establishmentId') establishmentId: string) {
    return this.purchases.list(establishmentId);
  }

  @Get('next-order-number')
  nextOrderNumber(@Param('establishmentId') establishmentId: string, @Query('supplierId') supplierId?: string) {
    return this.purchases.nextOrderNumber(establishmentId, supplierId).then((orderNumber) => ({ orderNumber }));
  }

  @Get(':purchaseId')
  get(@Param('establishmentId') establishmentId: string, @Param('purchaseId') purchaseId: string) {
    return this.purchases.get(establishmentId, purchaseId);
  }

  @Post()
  create(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Body() dto: CreatePurchaseDto) {
    return this.purchases.create(establishmentId, request.user!.sub, dto);
  }

  @Patch(':purchaseId')
  update(
    @Req() request: Request,
    @Param('establishmentId') establishmentId: string,
    @Param('purchaseId') purchaseId: string,
    @Body() dto: UpdatePurchaseDto,
  ) {
    return this.purchases.update(establishmentId, request.user!.sub, purchaseId, dto);
  }

  @Delete(':purchaseId')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Param('purchaseId') purchaseId: string) {
    return this.purchases.remove(establishmentId, request.user!.sub, purchaseId);
  }

  @Post(':purchaseId/receive')
  receive(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Param('purchaseId') purchaseId: string) {
    return this.purchases.receive(establishmentId, purchaseId, request.user!.sub);
  }

  @Post(':purchaseId/cancel')
  cancel(@Param('establishmentId') establishmentId: string, @Param('purchaseId') purchaseId: string) {
    return this.purchases.cancel(establishmentId, purchaseId);
  }
}
