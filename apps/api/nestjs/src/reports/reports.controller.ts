import { Controller, Get, Header, Param, Query, UseGuards } from '@nestjs/common';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { ReportQueryDto } from './dto/report-query.dto.js';
import { ReportsService } from './reports.service.js';

@Controller('establishments/:establishmentId/reports')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
@RequirePermissions('reports.view')
export class ReportsController {
  constructor(private readonly reports: ReportsService) {}

  @Get('summary')
  summary(@Param('establishmentId') establishmentId: string, @Query() query: ReportQueryDto) {
    return this.reports.summary(establishmentId, query);
  }

  @Get('payment-category-breakdown')
  paymentCategoryBreakdown(@Param('establishmentId') establishmentId: string, @Query() query: ReportQueryDto) {
    return this.reports.paymentCategoryBreakdown(establishmentId, query);
  }

  @Get('summary.csv')
  @Header('Content-Type', 'text/csv; charset=utf-8')
  @Header('Content-Disposition', 'attachment; filename="rapport.csv"')
  summaryCsv(@Param('establishmentId') establishmentId: string, @Query() query: ReportQueryDto) {
    return this.reports.summaryCsv(establishmentId, query);
  }
}
