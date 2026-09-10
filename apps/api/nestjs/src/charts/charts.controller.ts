import { Controller, Get, Param, Query, UseGuards } from '@nestjs/common';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { ChartsService } from './charts.service.js';
import {
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

@Controller('establishments/:establishmentId/charts')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
@RequirePermissions('reports.view')
export class ChartsController {
  constructor(private readonly charts: ChartsService) {}

  @Get('weekly')
  weekly(@Param('establishmentId') establishmentId: string, @Query() query: WeeklyChartQueryDto) {
    return this.charts.weeklyTotal(establishmentId, query.metric, query.weekStart);
  }

  @Get('weekly-by-category')
  weeklyByCategory(@Param('establishmentId') establishmentId: string, @Query() query: WeeklyByCategoryQueryDto) {
    return this.charts.weeklyByCategory(establishmentId, query.metric, query.weekStart, query.categoryIds);
  }

  @Get('weekly-by-product')
  weeklyByProduct(@Param('establishmentId') establishmentId: string, @Query() query: WeeklyByProductQueryDto) {
    return this.charts.weeklyByProduct(establishmentId, query.metric, query.weekStart, query.productId);
  }

  @Get('monthly')
  monthly(@Param('establishmentId') establishmentId: string, @Query() query: MonthlyChartQueryDto) {
    return this.charts.monthly(establishmentId, query.metric, query.year ? Number(query.year) : new Date().getFullYear());
  }

  @Get('top')
  top(@Param('establishmentId') establishmentId: string, @Query() query: TopChartQueryDto) {
    const now = new Date();
    const from = query.from ? new Date(query.from) : new Date(now.getFullYear(), 0, 1);
    const to = query.to ? new Date(query.to) : now;
    return this.charts.top(establishmentId, query.metric, from, to);
  }

  @Get('stock-lots')
  stockLots(@Param('establishmentId') establishmentId: string, @Query() query: StockLotsQueryDto) {
    const productIds = query.productIds.split(',').filter((id) => id.length > 0);
    return this.charts.stockLots(establishmentId, productIds);
  }

  @Get('out-of-stock-products')
  outOfStockProducts(@Param('establishmentId') establishmentId: string) {
    return this.charts.outOfStockProducts(establishmentId);
  }

  @Get('expenses/weekly')
  expensesWeekly(@Param('establishmentId') establishmentId: string, @Query() query: ExpenseWeeklyQueryDto) {
    return this.charts.expensesWeeklyTotal(establishmentId, query.weekStart);
  }

  @Get('expenses/weekly-by-category')
  expensesWeeklyByCategory(
    @Param('establishmentId') establishmentId: string,
    @Query() query: ExpenseWeeklyByCategoryQueryDto,
  ) {
    return this.charts.expensesWeeklyByCategory(establishmentId, query.weekStart, query.category);
  }

  @Get('expenses/monthly')
  expensesMonthly(@Param('establishmentId') establishmentId: string, @Query() query: ExpenseMonthlyQueryDto) {
    return this.charts.expensesMonthly(establishmentId, query.year ? Number(query.year) : new Date().getFullYear());
  }

  @Get('expenses/top')
  expensesTop(@Param('establishmentId') establishmentId: string, @Query() query: ExpenseTopQueryDto) {
    const now = new Date();
    const from = query.from ? new Date(query.from) : new Date(now.getFullYear(), 0, 1);
    const to = query.to ? new Date(query.to) : now;
    return this.charts.expensesTop(establishmentId, from, to);
  }
}
