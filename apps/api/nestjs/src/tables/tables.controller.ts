import { Body, Controller, Delete, Get, HttpCode, HttpStatus, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { CreateTableDto } from './dto/create-table.dto.js';
import { UpdateTableDto } from './dto/update-table.dto.js';
import { TablesService } from './tables.service.js';

@Controller('establishments/:establishmentId/tables')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
@RequirePermissions('tables.manage')
export class TablesController {
  constructor(private readonly tables: TablesService) {}

  @Get()
  list(@Param('establishmentId') establishmentId: string) {
    return this.tables.list(establishmentId);
  }

  @Post()
  create(@Param('establishmentId') establishmentId: string, @Body() dto: CreateTableDto) {
    return this.tables.create(establishmentId, dto);
  }

  @Patch(':tableId')
  update(@Param('establishmentId') establishmentId: string, @Param('tableId') tableId: string, @Body() dto: UpdateTableDto) {
    return this.tables.update(establishmentId, tableId, dto);
  }

  @Delete(':tableId')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(@Param('establishmentId') establishmentId: string, @Param('tableId') tableId: string) {
    return this.tables.remove(establishmentId, tableId);
  }
}
