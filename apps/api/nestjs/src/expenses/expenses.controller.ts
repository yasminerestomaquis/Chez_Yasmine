import { Body, Controller, Delete, Get, HttpCode, HttpStatus, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { CreateExpenseDto, UpdateExpenseDto } from './dto/expense.dto.js';
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
