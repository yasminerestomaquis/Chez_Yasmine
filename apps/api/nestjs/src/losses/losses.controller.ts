import { Body, Controller, Get, Param, Post, Req, UseGuards } from '@nestjs/common';
import type { Request } from 'express';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { CreateLossDto } from './dto/create-loss.dto.js';
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
}
