import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import type { CreateCategoryDto } from './dto/create-category.dto.js';
import type { UpdateCategoryDto } from './dto/update-category.dto.js';

// PermissionsGuard checks establishment membership, but Prisma itself connects
// directly to Postgres (bypassing RLS, unlike the PostgREST anon/authenticated
// path) — every query here must scope by establishmentId explicitly, it is
// never enforced automatically at this layer.
@Injectable()
export class CategoriesService {
  constructor(private readonly prisma: PrismaService) {}

  list(establishmentId: string) {
    return this.prisma.category.findMany({ where: { establishmentId }, orderBy: { name: 'asc' } });
  }

  create(establishmentId: string, dto: CreateCategoryDto) {
    return this.prisma.category.create({
      data: {
        establishmentId,
        name: dto.name,
        hasVariablePricing: dto.hasVariablePricing,
        hasCasePricing: dto.hasCasePricing,
      },
    });
  }

  async update(establishmentId: string, categoryId: string, dto: UpdateCategoryDto) {
    const { count } = await this.prisma.category.updateMany({
      where: { id: categoryId, establishmentId },
      data: dto,
    });
    if (count === 0) {
      throw new NotFoundException('Catégorie introuvable pour cet établissement');
    }
    return this.prisma.category.findUniqueOrThrow({ where: { id: categoryId } });
  }

  async remove(establishmentId: string, categoryId: string): Promise<void> {
    const { count } = await this.prisma.category.deleteMany({ where: { id: categoryId, establishmentId } });
    if (count === 0) {
      throw new NotFoundException('Catégorie introuvable pour cet établissement');
    }
  }
}
