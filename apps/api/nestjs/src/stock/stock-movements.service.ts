import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import type { CreateStockMovementDto } from './dto/create-stock-movement.dto.js';
import { applyStockMovement, isLowStock } from './stock-math.js';

@Injectable()
export class StockMovementsService {
  constructor(private readonly prisma: PrismaService) {}

  private async getProductOrThrow(establishmentId: string, productId: string) {
    const product = await this.prisma.product.findFirst({ where: { id: productId, establishmentId } });
    if (!product) {
      throw new NotFoundException('Produit introuvable pour cet établissement');
    }
    return product;
  }

  async create(establishmentId: string, productId: string, userId: string, dto: CreateStockMovementDto) {
    const product = await this.getProductOrThrow(establishmentId, productId);

    let nextQuantity: number;
    try {
      nextQuantity = applyStockMovement(product.stockQuantity.toNumber(), dto);
    } catch (error) {
      throw new BadRequestException(error instanceof Error ? error.message : 'Mouvement de stock invalide');
    }

    const [, movement] = await this.prisma.$transaction([
      this.prisma.product.update({ where: { id: productId }, data: { stockQuantity: nextQuantity } }),
      this.prisma.stockMovement.create({
        data: { productId, type: dto.type, quantity: dto.quantity, reason: dto.reason, createdBy: userId },
      }),
    ]);
    return movement;
  }

  async listForProduct(establishmentId: string, productId: string) {
    await this.getProductOrThrow(establishmentId, productId);
    return this.prisma.stockMovement.findMany({ where: { productId }, orderBy: { createdAt: 'desc' } });
  }

  /**
   * Products at or below their alert threshold. Comparing two columns of the
   * same row (stockQuantity vs minStock) isn't expressible in a plain Prisma
   * `where`, so this filters in application code — fine at MVP catalog
   * sizes; revisit with a raw query or a view if that stops being true.
   */
  async listLowStockAlerts(establishmentId: string) {
    const products = await this.prisma.product.findMany({
      where: { establishmentId, status: 'active', minStock: { gt: 0 } },
      select: { id: true, name: true, stockQuantity: true, minStock: true },
    });
    return products
      .filter((p) => isLowStock(p.stockQuantity.toNumber(), p.minStock.toNumber()))
      .map((p) => ({ id: p.id, name: p.name, stockQuantity: p.stockQuantity.toNumber(), minStock: p.minStock.toNumber() }));
  }
}
