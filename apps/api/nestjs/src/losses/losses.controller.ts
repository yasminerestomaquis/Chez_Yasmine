import { Body, Controller, Delete, Get, HttpCode, HttpStatus, Param, Patch, Post, Req, UseGuards } from '@nestjs/common';
import type { Request } from 'express';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { CreateLossDto } from './dto/create-loss.dto.js';
import { UpdateLossDto } from './dto/update-loss.dto.js';
import { LossesService } from './losses.service.js';

@Controller('establishments/:establishmentId/losses')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
@RequirePermissions('losses.manage')
export class LossesController {
  constructor(private readonly losses: LossesService) {}

  @Get()
  list(@Param('establishmentId') establishmentId: string) {
    return this.losses.list(establishmentId);
  }

  @Post()
  create(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Body() dto: CreateLossDto) {
    return this.losses.create(establishmentId, request.user!.sub, dto);
  }

  /** `losses.edit` (Super Administrateur/Gérant/Serveur) remplace `losses.manage` de la classe pour ces deux routes (`getAllAndOverride`). */
  @Patch(':lossId')
  @RequirePermissions('losses.edit')
  update(
    @Req() request: Request,
    @Param('establishmentId') establishmentId: string,
    @Param('lossId') lossId: string,
    @Body() dto: UpdateLossDto,
  ) {
    return this.losses.update(establishmentId, request.user!.sub, lossId, dto);
  }

  @Delete(':lossId')
  @HttpCode(HttpStatus.NO_CONTENT)
  @RequirePermissions('losses.edit')
  remove(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Param('lossId') lossId: string) {
    return this.losses.remove(establishmentId, request.user!.sub, lossId);
  }
}
