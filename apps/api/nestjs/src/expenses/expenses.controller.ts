import { Body, Controller, Delete, Get, HttpCode, HttpStatus, Param, Patch, Post, Query, Res, UseGuards } from '@nestjs/common';
import type { Response } from 'express';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { CreateExpenseDto, ExpenseHistoryQueryDto, UpdateExpenseDto } from './dto/expense.dto.js';
import { ExpensesService } from './expenses.service.js';

@Controller('establishments/:establishmentId/expenses')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
@RequirePermissions('expenses.manage')
export class ExpensesController {
  constructor(private readonly expenses: ExpensesService) {}

  @Get()
  list(@Param('establishmentId') establishmentId: string, @Query('from') from?: string, @Query('to') to?: string) {
    return this.expenses.list(establishmentId, { from, to });
  }

  @Get('next-market-number')
  nextMarketNumber(@Param('establishmentId') establishmentId: string) {
    return this.expenses.nextMarketNumber(establishmentId).then((marketNumber) => ({ marketNumber }));
  }

  @Get('summary')
  summary(
    @Param('establishmentId') establishmentId: string,
    @Query('period') period: 'year' | 'month' | 'week',
    @Query('year') year: string,
    @Query('month') month?: string,
    @Query('weekOf') weekOf?: string,
  ) {
    return this.expenses.summary(establishmentId, {
      period,
      year: Number(year),
      month: month ? Number(month) : undefined,
      weekOf,
    });
  }

  @Get('history')
  history(@Param('establishmentId') establishmentId: string, @Query() query: ExpenseHistoryQueryDto) {
    return this.expenses.history(establishmentId, query);
  }

  @Get('history.xlsx')
  async historyExcel(
    @Param('establishmentId') establishmentId: string,
    @Query() query: ExpenseHistoryQueryDto,
    @Res({ passthrough: true }) res: Response,
  ) {
    const { buffer, filename } = await this.expenses.exportHistoryExcel(establishmentId, query);
    res.set({
      'Content-Type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'Content-Disposition': `attachment; filename="${filename}"`,
    });
    return buffer;
  }

  @Post()
  create(@Param('establishmentId') establishmentId: string, @Body() dto: CreateExpenseDto) {
    return this.expenses.create(establishmentId, dto);
  }

  @Patch(':expenseId')
  update(
    @Param('establishmentId') establishmentId: string,
    @Param('expenseId') expenseId: string,
    @Body() dto: UpdateExpenseDto,
  ) {
    return this.expenses.update(establishmentId, expenseId, dto);
  }

  @Delete(':expenseId')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(@Param('establishmentId') establishmentId: string, @Param('expenseId') expenseId: string) {
    return this.expenses.remove(establishmentId, expenseId);
  }
}
