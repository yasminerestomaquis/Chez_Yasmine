import { Body, Controller, Get, Param, Post, Req, UseGuards } from '@nestjs/common';
import type { Request } from 'express';
import { AuthorizationService } from '../auth/authorization.service.js';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { CreateStockMovementDto } from './dto/create-stock-movement.dto.js';
import { StockMovementsService } from './stock-movements.service.js';
import { stockPermissionsOf } from './stock-permissions.js';

@Controller('establishments/:establishmentId')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
@RequirePermissions('stock.manage')
export class StockController {
  constructor(
    private readonly stockMovements: StockMovementsService,
    private readonly authorization: AuthorizationService,
  ) {}

  /**
   * Permissions Stock à bascule client détenues par l'utilisateur (pour
   * l'instant, seulement `stock.view_value` — visibilité du groupe « Valeur
   * du stock », demande utilisateur du 2026-09-22) — même principe que
   * `ChartsController.myPermissions`.
   */
  @Get('stock/permissions')
  @RequirePermissions('stock.view')
  async myPermissions(@Req() request: Request, @Param('establishmentId') establishmentId: string) {
    const userId = request.user?.sub;
    const granted = userId ? await this.authorization.getPermissionCodes(userId, establishmentId) : new Set<string>();
    return { permissions: stockPermissionsOf(granted) };
  }

  @Post('products/:productId/stock-movements')
  create(
    @Req() request: Request,
    @Param('establishmentId') establishmentId: string,
    @Param('productId') productId: string,
    @Body() dto: CreateStockMovementDto,
  ) {
    return this.stockMovements.create(establishmentId, productId, request.user!.sub, dto);
  }

  // Lecture (`stock.view`) séparée de la gestion (`stock.manage`, niveau
  // contrôleur ci-dessus) : consulter l'historique/les alertes ne doit pas
  // exiger le droit de créer un mouvement — voir supabase/seed/001_roles_permissions.sql
  // (2026-09-11, Serveur : lecture seule du Stock).
  @Get('products/:productId/stock-movements')
  @RequirePermissions('stock.view')
  listForProduct(@Param('establishmentId') establishmentId: string, @Param('productId') productId: string) {
    return this.stockMovements.listForProduct(establishmentId, productId);
  }

  @Get('products/:productId/order-numbers')
  @RequirePermissions('stock.view')
  orderNumbers(@Param('establishmentId') establishmentId: string, @Param('productId') productId: string) {
    return this.stockMovements.orderNumbers(establishmentId, productId);
  }

  @Get('stock/alerts')
  @RequirePermissions('stock.view')
  listLowStockAlerts(@Param('establishmentId') establishmentId: string) {
    return this.stockMovements.listLowStockAlerts(establishmentId);
  }

  @Get('stock/movement-totals')
  @RequirePermissions('stock.view')
  listMovementTotals(@Param('establishmentId') establishmentId: string) {
    return this.stockMovements.listMovementTotals(establishmentId);
  }
}
