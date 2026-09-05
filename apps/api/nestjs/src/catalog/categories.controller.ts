import { Body, Controller, Delete, Get, HttpCode, HttpStatus, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { CategoriesService } from './categories.service.js';
import { CreateCategoryDto } from './dto/create-category.dto.js';
import { UpdateCategoryDto } from './dto/update-category.dto.js';

@Controller('establishments/:establishmentId/categories')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
export class CategoriesController {
  constructor(private readonly categories: CategoriesService) {}

  @Get()
  @RequirePermissions('products.manage')
  list(@Param('establishmentId') establishmentId: string) {
    return this.categories.list(establishmentId);
  }

  @Post()
  @RequirePermissions('products.manage')
  create(@Param('establishmentId') establishmentId: string, @Body() dto: CreateCategoryDto) {
    return this.categories.create(establishmentId, dto);
  }

  @Patch(':categoryId')
  @RequirePermissions('products.manage')
  update(
    @Param('establishmentId') establishmentId: string,
    @Param('categoryId') categoryId: string,
    @Body() dto: UpdateCategoryDto,
  ) {
    return this.categories.update(establishmentId, categoryId, dto);
  }

  @Delete(':categoryId')
  @RequirePermissions('products.manage')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(@Param('establishmentId') establishmentId: string, @Param('categoryId') categoryId: string) {
    return this.categories.remove(establishmentId, categoryId);
  }
}
