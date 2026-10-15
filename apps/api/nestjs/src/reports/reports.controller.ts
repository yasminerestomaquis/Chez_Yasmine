import { Controller, ForbiddenException, Get, Header, Param, Query, Req, StreamableFile, UseGuards } from '@nestjs/common';
import type { Request } from 'express';
import { AuthorizationService } from '../auth/authorization.service.js';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { BeveragesSoldQueryDto } from './dto/beverages-sold-query.dto.js';
import { PlatsSoldQueryDto } from './dto/plats-sold-query.dto.js';
import { ReportQueryDto } from './dto/report-query.dto.js';
import {
  REPORTS_BEVERAGES_SOLD_PERMISSION,
  REPORTS_EXPORT_PERMISSION,
  REPORTS_PLATS_SOLD_PERMISSION,
  reportsPermissionsOf,
} from './report-permissions.js';
import { canViewHome, homePermissionsOf, maskBreakdown } from './home-permissions.js';
import { ReportsService } from './reports.service.js';

@Controller('establishments/:establishmentId/reports')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
@RequirePermissions('reports.view')
export class ReportsController {
  constructor(
    private readonly reports: ReportsService,
    private readonly authorization: AuthorizationService,
  ) {}

  private async require(request: Request, establishmentId: string, code: string): Promise<void> {
    const userId = request.user?.sub;
    const allowed = userId ? await this.authorization.hasAllPermissions(userId, establishmentId, [code]) : false;
    if (!allowed) {
      throw new ForbiddenException(`Permission(s) manquante(s) : ${code}`);
    }
  }

  /** Boutons Rapports que l'appelant a le droit d'utiliser — l'écran masque les autres (voir report-permissions.ts). */
  @Get('permissions')
  async myPermissions(@Req() request: Request, @Param('establishmentId') establishmentId: string) {
    const userId = request.user?.sub;
    const granted = userId ? await this.authorization.getPermissionCodes(userId, establishmentId) : new Set<string>();
    return { permissions: reportsPermissionsOf(granted) };
  }

  /**
   * Droit de voir l'Accueil : `reports.view` OU au moins une rubrique `home.*`
   * (un rôle peut se voir accorder une seule carte sans accès au module
   * Rapports). `@RequirePermissions()` vide sur les routes concernées
   * neutralise la permission de classe ; ce contrôle la remplace — un non-membre
   * n'a aucun code, donc est refusé.
   */
  private async homeGrants(request: Request, establishmentId: string): Promise<Set<string>> {
    const userId = request.user?.sub;
    const granted = userId ? await this.authorization.getPermissionCodes(userId, establishmentId) : new Set<string>();
    if (!granted.has('reports.view') && !canViewHome(granted)) {
      throw new ForbiddenException('Permission(s) manquante(s) : reports.view ou une rubrique home.*');
    }
    return granted;
  }

  /** Rubriques de l'Accueil que l'appelant a le droit de voir (voir home-permissions.ts). */
  @Get('home-permissions')
  @RequirePermissions()
  async myHomePermissions(@Req() request: Request, @Param('establishmentId') establishmentId: string) {
    const userId = request.user?.sub;
    const granted = userId ? await this.authorization.getPermissionCodes(userId, establishmentId) : new Set<string>();
    return { permissions: homePermissionsOf(granted) };
  }

  /** Cartes « Commandes » et « Alertes stock » de l'Accueil — uniquement les chiffres accordés (home.orders / home.stock_alerts). */
  @Get('home-summary')
  @RequirePermissions()
  async homeSummary(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Query() query: ReportQueryDto) {
    const granted = await this.homeGrants(request, establishmentId);
    const summary = await this.reports.summary(establishmentId, query);
    return {
      salesCount: granted.has('home.orders') ? summary.salesCount : 0,
      lowStockCount: granted.has('home.stock_alerts') ? summary.lowStockCount : 0,
    };
  }

  @Get('summary')
  summary(@Param('establishmentId') establishmentId: string, @Query() query: ReportQueryDto) {
    return this.reports.summary(establishmentId, query);
  }

  /** Recettes de l'Accueil : chaque chiffre n'est renvoyé que si sa rubrique `home.*` est accordée (sinon 0), voir `maskBreakdown`. */
  @Get('payment-category-breakdown')
  @RequirePermissions()
  async paymentCategoryBreakdown(
    @Req() request: Request,
    @Param('establishmentId') establishmentId: string,
    @Query() query: ReportQueryDto,
  ) {
    const granted = await this.homeGrants(request, establishmentId);
    return maskBreakdown(await this.reports.paymentCategoryBreakdown(establishmentId, query), granted);
  }

  @Get('summary.csv')
  @Header('Content-Type', 'text/csv; charset=utf-8')
  @Header('Content-Disposition', 'attachment; filename="rapport.csv"')
  async summaryCsv(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Query() query: ReportQueryDto) {
    await this.require(request, establishmentId, REPORTS_EXPORT_PERMISSION);
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
    @Req() request: Request,
    @Param('establishmentId') establishmentId: string,
    @Query() query: BeveragesSoldQueryDto,
  ): Promise<StreamableFile> {
    await this.require(request, establishmentId, REPORTS_BEVERAGES_SOLD_PERMISSION);
    const { buffer, filename } = await this.reports.beveragesSoldPdf(establishmentId, query.dates);
    return new StreamableFile(buffer, {
      type: 'application/pdf',
      disposition: `attachment; filename="${filename}"`,
    });
  }

  /** Même principe que beveragesSoldPdf ci-dessus, pour les catégories à prix variable (Poulets/Poissons/Plats africains). */
  @Get('plats-sold.pdf')
  async platsSoldPdf(
    @Req() request: Request,
    @Param('establishmentId') establishmentId: string,
    @Query() query: PlatsSoldQueryDto,
  ): Promise<StreamableFile> {
    await this.require(request, establishmentId, REPORTS_PLATS_SOLD_PERMISSION);
    const { buffer, filename } = await this.reports.platsSoldPdf(establishmentId, query.dates);
    return new StreamableFile(buffer, {
      type: 'application/pdf',
      disposition: `attachment; filename="${filename}"`,
    });
  }
}
