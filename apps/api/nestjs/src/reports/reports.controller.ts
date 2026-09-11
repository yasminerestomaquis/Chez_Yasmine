import { Controller, Get, Header, Param, Query, Res, UseGuards } from '@nestjs/common';
import type { Response } from 'express';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { BeveragesSoldQueryDto } from './dto/beverages-sold-query.dto.js';
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

  /** Nom de fichier dépendant de la date choisie par l'utilisateur — `@Header` n'accepte qu'une valeur statique, d'où `@Res({ passthrough: true })`. */
  @Get('beverages-sold.xlsx')
  async beveragesSoldExcel(
    @Param('establishmentId') establishmentId: string,
    @Query() query: BeveragesSoldQueryDto,
    @Res({ passthrough: true }) res: Response,
  ) {
    const { buffer, filename } = await this.reports.beveragesSoldExcel(establishmentId, query.date);
    res.set({
      'Content-Type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'Content-Disposition': `attachment; filename="${filename}"`,
    });
    return buffer;
  }
}
