import { Controller, Get, Header, Param, Query, StreamableFile, UseGuards } from '@nestjs/common';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { BeveragesSoldQueryDto } from './dto/beverages-sold-query.dto.js';
import { PlatsSoldQueryDto } from './dto/plats-sold-query.dto.js';
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

  /**
   * `StreamableFile` (pas un `Buffer` brut) : NestJS n'a pas de cas
   * particulier pour un `Buffer` retourné via `@Res({ passthrough: true })`
   * — `ExpressAdapter.reply()` teste seulement `isObject(body)` (vrai pour
   * un Buffer, `typeof buffer === 'object'`) et appelle alors
   * `response.json(body)`, qui sérialise le buffer en
   * `{"type":"Buffer","data":[...]}` au lieu de l'envoyer en binaire — fichier
   * téléchargé du bon nom/de la bonne extension mais illisible par tout
   * lecteur PDF (constaté par l'utilisateur, 2026-09-25, après la régénération
   * de package-lock.json qui a fait passer @nestjs/platform-express de 12.0.1
   * à 12.1.0 ; probablement déjà latent avec l'export Excel équivalent avant
   * ce commit, jamais rouvert en conditions réelles). `StreamableFile` est le
   * seul type explicitement court-circuité avant cette branche `isObject`.
   */
  @Get('beverages-sold.pdf')
  async beveragesSoldPdf(
    @Param('establishmentId') establishmentId: string,
    @Query() query: BeveragesSoldQueryDto,
  ): Promise<StreamableFile> {
    const { buffer, filename } = await this.reports.beveragesSoldPdf(establishmentId, query.dates);
    return new StreamableFile(buffer, {
      type: 'application/pdf',
      disposition: `attachment; filename="${filename}"`,
    });
  }

  /** Même principe que beveragesSoldPdf ci-dessus, pour les catégories à prix variable (Poulets/Poissons/Plats africains). */
  @Get('plats-sold.pdf')
  async platsSoldPdf(
    @Param('establishmentId') establishmentId: string,
    @Query() query: PlatsSoldQueryDto,
  ): Promise<StreamableFile> {
    const { buffer, filename } = await this.reports.platsSoldPdf(establishmentId, query.dates);
    return new StreamableFile(buffer, {
      type: 'application/pdf',
      disposition: `attachment; filename="${filename}"`,
    });
  }
}
