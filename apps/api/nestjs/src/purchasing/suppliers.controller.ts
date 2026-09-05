import { Body, Controller, Delete, Get, HttpCode, HttpStatus, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { CreateSupplierDto, UpdateSupplierDto } from './dto/supplier.dto.js';
import { SuppliersService } from './suppliers.service.js';

@Controller('establishments/:establishmentId/suppliers')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
@RequirePermissions('purchases.manage')
export class SuppliersController {
  constructor(private readonly suppliers: SuppliersService) {}

  @Get()
  list(@Param('establishmentId') establishmentId: string) {
    return this.suppliers.list(establishmentId);
  }

  @Post()
  create(@Param('establishmentId') establishmentId: string, @Body() dto: CreateSupplierDto) {
    return this.suppliers.create(establishmentId, dto);
  }

  @Patch(':supplierId')
  update(
    @Param('establishmentId') establishmentId: string,
    @Param('supplierId') supplierId: string,
    @Body() dto: UpdateSupplierDto,
  ) {
    return this.suppliers.update(establishmentId, supplierId, dto);
  }

  @Delete(':supplierId')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(@Param('establishmentId') establishmentId: string, @Param('supplierId') supplierId: string) {
    return this.suppliers.remove(establishmentId, supplierId);
  }
}
