import { Body, Controller, Param, Post, Req, UseGuards } from '@nestjs/common';
import type { Request } from 'express';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { SyncBatchDto } from './dto/sync-batch.dto.js';
import { SyncService } from './sync.service.js';

/**
 * No @RequirePermissions here: a batch can mix operation types that each
 * need a different permission (sale vs stock movement) — SyncService checks
 * the right one per operation instead of gating the whole route on one.
 */
@Controller('establishments/:establishmentId/sync')
@UseGuards(SupabaseJwtGuard)
export class SyncController {
  constructor(private readonly sync: SyncService) {}

  @Post()
  processBatch(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Body() dto: SyncBatchDto) {
    return this.sync.processBatch(establishmentId, request.user!.sub, dto.operations);
  }
}
