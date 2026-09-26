import { Body, Controller, Get, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import type { Request } from 'express';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { CorrectReferencePricedItemDto } from './dto/correct-reference-priced-item.dto.js';
import { CreateSaleDto } from './dto/create-sale.dto.js';
import { UpdateSaleItemDto } from './dto/update-sale-item.dto.js';
import { UpdateSalePaymentDto } from './dto/update-sale-payment.dto.js';
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

  /** `from`/`to` (ISO complet, date+heure) prévalent sur `day` quand fournis ensemble — voir SalesService.listForRange. */
  @Get()
  @RequirePermissions('pos.sell')
  listForDay(
    @Param('establishmentId') establishmentId: string,
    @Query('day') day: string,
    @Query('from') from?: string,
    @Query('to') to?: string,
  ) {
    if (from && to) {
      return this.sales.listForRange(establishmentId, from, to);
    }
    return this.sales.listForDay(establishmentId, day ?? new Date().toISOString().slice(0, 10));
  }

  @Post(':saleId/refund')
  @RequirePermissions('pos.refund')
  refund(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Param('saleId') saleId: string) {
    return this.sales.refund(establishmentId, request.user!.sub, saleId);
  }

  /**
   * Corrige le nombre de produits vendus d'une ligne — voir SalesService.updateItemQuantity.
   * `pos.correct` (2026-09-16) — volontairement distincte de `pos.refund` : corriger une
   * quantité/un mode de paiement n'annule pas la vente, contrairement à un remboursement
   * complet. Sépare les deux pour pouvoir accorder l'une sans l'autre (ex. Serveur).
   */
  @Patch(':saleId/items/:itemId')
  @RequirePermissions('pos.correct')
  updateItemQuantity(
    @Req() request: Request,
    @Param('establishmentId') establishmentId: string,
    @Param('saleId') saleId: string,
    @Param('itemId') itemId: string,
    @Body() dto: UpdateSaleItemDto,
  ) {
    return this.sales.updateItemQuantity(establishmentId, request.user!.sub, saleId, itemId, dto.quantity);
  }

  /** Corrige une ligne à prix de référence variable (ex. Gbêlê) via le montant payé — voir SalesService.correctReferencePricedItem. */
  @Patch(':saleId/items/:itemId/amount')
  @RequirePermissions('pos.correct')
  correctReferencePricedItem(
    @Req() request: Request,
    @Param('establishmentId') establishmentId: string,
    @Param('saleId') saleId: string,
    @Param('itemId') itemId: string,
    @Body() dto: CorrectReferencePricedItemDto,
  ) {
    return this.sales.correctReferencePricedItem(establishmentId, request.user!.sub, saleId, itemId, dto.amountPaid);
  }

  /** Corrige le mode de paiement (Espèces/Mobile Money) d'une ligne — voir SalesService.updatePaymentMethod. */
  @Patch(':saleId/payments/:paymentId')
  @RequirePermissions('pos.correct')
  updatePaymentMethod(
    @Param('establishmentId') establishmentId: string,
    @Param('saleId') saleId: string,
    @Param('paymentId') paymentId: string,
    @Body() dto: UpdateSalePaymentDto,
  ) {
    return this.sales.updatePaymentMethod(establishmentId, saleId, paymentId, dto.method);
  }
}
