import { Body, Controller, Delete, Get, HttpCode, HttpStatus, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { CreateProductDto } from './dto/create-product.dto.js';
import { UpdateProductDto } from './dto/update-product.dto.js';
import { ProductsService } from './products.service.js';

@Controller('establishments/:establishmentId/products')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
export class ProductsController {
  constructor(private readonly products: ProductsService) {}

  @Get()
  @RequirePermissions('products.manage')
  list(@Param('establishmentId') establishmentId: string) {
    return this.products.list(establishmentId);
  }

  @Get(':productId')
  @RequirePermissions('products.manage')
  get(@Param('establishmentId') establishmentId: string, @Param('productId') productId: string) {
    return this.products.get(establishmentId, productId);
  }

  @Post()
  @RequirePermissions('products.manage')
  create(@Param('establishmentId') establishmentId: string, @Body() dto: CreateProductDto) {
    return this.products.create(establishmentId, dto);
  }

  @Patch(':productId')
  @RequirePermissions('products.manage')
  update(
    @Param('establishmentId') establishmentId: string,
    @Param('productId') productId: string,
    @Body() dto: UpdateProductDto,
  ) {
    return this.products.update(establishmentId, productId, dto);
  }

  @Delete(':productId')
  @RequirePermissions('products.manage')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(@Param('establishmentId') establishmentId: string, @Param('productId') productId: string) {
    return this.products.remove(establishmentId, productId);
  }
}
