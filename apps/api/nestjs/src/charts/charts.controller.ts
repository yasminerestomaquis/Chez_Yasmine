import { Controller, ForbiddenException, Get, Param, Query, Req, StreamableFile, UseGuards } from '@nestjs/common';
import type { Request } from 'express';
import { AuthorizationService } from '../auth/authorization.service.js';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import {
  chartPermissionsOf,
  expenseChartPermission,
  metricChartPermission,
  PROFIT_MEALS_LISTING_PERMISSION,
  STOCK_LOTS_PERMISSION,
  STOCK_OUT_PERMISSION,
} from './chart-permissions.js';
import { STOCK_ACTIVE_LISTING_PERMISSION } from '../stock/stock-permissions.js';
import { ChartsService } from './charts.service.js';
import {
  ActiveStockListingQueryDto,
  MonthlyChartQueryDto,
  StockLotsQueryDto,
  TopChartQueryDto,
  WeeklyByCategoryQueryDto,
  WeeklyByProductQueryDto,
  WeeklyChartQueryDto,
} from './dto/chart-query.dto.js';
import {
  ExpenseMonthlyQueryDto,
  ExpenseTopQueryDto,
  ExpenseWeeklyByCategoryQueryDto,
  ExpenseWeeklyQueryDto,
} from './dto/expense-chart-query.dto.js';

/**
 * Une permission par graphique (`charts.*`, voir chart-permissions.ts) au lieu
 * du `reports.view` global d'origine : `PermissionsGuard` ne peut gater qu'un
 * code statique par route alors que le code dépend ici du paramètre `metric`
 * (Recettes/Bénéfices), donc la vérification se fait dans chaque méthode. Un
 * non-membre de l'établissement n'a aucun code -> refusé partout.
 */
@Controller('establishments/:establishmentId/charts')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
export class ChartsController {
  constructor(
    private readonly charts: ChartsService,
    private readonly authorization: AuthorizationService,
  ) {}

  private async require(request: Request, establishmentId: string, code: string): Promise<void> {
    const userId = request.user?.sub;
    const allowed = userId ? await this.authorization.hasAllPermissions(userId, establishmentId, [code]) : false;
    if (!allowed) {
      throw new ForbiddenException(`Permission(s) manquante(s) : ${code}`);
    }
  }

  /** Graphiques que l'appelant a le droit de voir — l'écran Graphiques masque les autres. */
  @Get('permissions')
  async myPermissions(@Req() request: Request, @Param('establishmentId') establishmentId: string) {
    const userId = request.user?.sub;
    const granted = userId ? await this.authorization.getPermissionCodes(userId, establishmentId) : new Set<string>();
    return { permissions: chartPermissionsOf(granted) };
  }

  @Get('weekly')
  async weekly(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Query() query: WeeklyChartQueryDto) {
    await this.require(request, establishmentId, metricChartPermission(query.metric, 'daily'));
    return this.charts.weeklyTotal(establishmentId, query.metric, query.weekStart);
  }

  @Get('weekly-by-category')
  async weeklyByCategory(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Query() query: WeeklyByCategoryQueryDto) {
    await this.require(request, establishmentId, metricChartPermission(query.metric, 'by_category'));
    return this.charts.weeklyByCategory(establishmentId, query.metric, query.weekStart, query.categoryIds);
  }

  @Get('weekly-by-product')
  async weeklyByProduct(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Query() query: WeeklyByProductQueryDto) {
    await this.require(request, establishmentId, metricChartPermission(query.metric, 'by_product'));
    return this.charts.weeklyByProduct(establishmentId, query.metric, query.weekStart, query.productId, query.productIds);
  }

  @Get('monthly')
  async monthly(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Query() query: MonthlyChartQueryDto) {
    await this.require(request, establishmentId, metricChartPermission(query.metric, 'monthly'));
    return this.charts.monthly(establishmentId, query.metric, query.year ? Number(query.year) : new Date().getFullYear());
  }

  @Get('top')
  async top(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Query() query: TopChartQueryDto) {
    await this.require(request, establishmentId, metricChartPermission(query.metric, 'top'));
    const now = new Date();
    const from = query.from ? new Date(query.from) : new Date(now.getFullYear(), 0, 1);
    const to = query.to ? new Date(query.to) : now;
    return this.charts.top(establishmentId, query.metric, from, to);
  }

  @Get('stock-lots')
  async stockLots(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Query() query: StockLotsQueryDto) {
    await this.require(request, establishmentId, STOCK_LOTS_PERMISSION);
    const productIds = query.productIds.split(',').filter((id) => id.length > 0);
    return this.charts.stockLots(establishmentId, productIds);
  }

  @Get('out-of-stock-products')
  async outOfStockProducts(@Req() request: Request, @Param('establishmentId') establishmentId: string) {
    await this.require(request, establishmentId, STOCK_OUT_PERMISSION);
    return this.charts.outOfStockProducts(establishmentId);
  }

  /**
   * Listing "Stock actif" (module Stock — demande utilisateur du
   * 2026-09-25) : une agrégation par produit des mêmes lots FIFO actifs que
   * `stock-lots`. Permission dédiée (`stock.active_listing`, pas
   * `charts.stock_lots`) pour rester accordable/révocable indépendamment
   * depuis « Gestion des permissions » — par défaut Super Administrateur
   * seul (voir supabase/seed/001_roles_permissions.sql).
   */
  @Get('active-stock-listing')
  async activeStockListing(
    @Req() request: Request,
    @Param('establishmentId') establishmentId: string,
    @Query() query: ActiveStockListingQueryDto,
  ) {
    await this.require(request, establishmentId, STOCK_ACTIVE_LISTING_PERMISSION);
    const categoryIds = query.categoryIds?.split(',').filter((id) => id.length > 0);
    return this.charts.activeStockListing(establishmentId, categoryIds);
  }

  @Get('active-stock-listing.pdf')
  async activeStockListingPdf(
    @Req() request: Request,
    @Param('establishmentId') establishmentId: string,
    @Query() query: ActiveStockListingQueryDto,
  ): Promise<StreamableFile> {
    await this.require(request, establishmentId, STOCK_ACTIVE_LISTING_PERMISSION);
    const categoryIds = query.categoryIds?.split(',').filter((id) => id.length > 0);
    const { buffer, filename } = await this.charts.activeStockListingPdf(establishmentId, categoryIds);
    return new StreamableFile(buffer, { type: 'application/pdf', disposition: `attachment; filename="${filename}"` });
  }

  /**
   * Listing "Repas" (onglet Bénéfices — demande utilisateur du 2026-09-25) :
   * cumule Plats africains/Poissons/Poulets en une seule ligne, aucun
   * paramètre (tout l'historique, pas de filtre de période).
   */
  @Get('meals-profit-listing')
  async mealsProfitListing(@Req() request: Request, @Param('establishmentId') establishmentId: string) {
    await this.require(request, establishmentId, PROFIT_MEALS_LISTING_PERMISSION);
    return this.charts.mealsProfitListing(establishmentId);
  }

  @Get('meals-profit-listing.pdf')
  async mealsProfitListingPdf(@Req() request: Request, @Param('establishmentId') establishmentId: string): Promise<StreamableFile> {
    await this.require(request, establishmentId, PROFIT_MEALS_LISTING_PERMISSION);
    const { buffer, filename } = await this.charts.mealsProfitListingPdf(establishmentId);
    return new StreamableFile(buffer, { type: 'application/pdf', disposition: `attachment; filename="${filename}"` });
  }

  @Get('expenses/weekly')
  async expensesWeekly(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Query() query: ExpenseWeeklyQueryDto) {
    await this.require(request, establishmentId, expenseChartPermission('daily'));
    return this.charts.expensesWeeklyTotal(establishmentId, query.weekStart);
  }

  @Get('expenses/weekly-by-category')
  async expensesWeeklyByCategory(
    @Req() request: Request,
    @Param('establishmentId') establishmentId: string,
    @Query() query: ExpenseWeeklyByCategoryQueryDto,
  ) {
    await this.require(request, establishmentId, expenseChartPermission('by_category'));
    return this.charts.expensesWeeklyByCategory(establishmentId, query.weekStart, query.categories);
  }

  @Get('expenses/monthly')
  async expensesMonthly(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Query() query: ExpenseMonthlyQueryDto) {
    await this.require(request, establishmentId, expenseChartPermission('monthly'));
    return this.charts.expensesMonthly(establishmentId, query.year ? Number(query.year) : new Date().getFullYear());
  }

  @Get('expenses/top')
  async expensesTop(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Query() query: ExpenseTopQueryDto) {
    await this.require(request, establishmentId, expenseChartPermission('top'));
    const now = new Date();
    const from = query.from ? new Date(query.from) : new Date(now.getFullYear(), 0, 1);
    const to = query.to ? new Date(query.to) : now;
    return this.charts.expensesTop(establishmentId, from, to);
  }
}
