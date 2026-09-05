import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import { applyStockMovement } from '../stock/stock-math.js';
import type { CreateLossDto } from './dto/create-loss.dto.js';

@Injectable()
export class LossesService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Records a stock loss for accounting purposes: writes both a
   * StockMovement (type 'loss', decrementing the product) and a Loss row
   * (quantity + reason, for reporting) in one transaction — the only path
   * that creates a 'loss' movement since Phase 12 (see the comment on
   * CreateStockMovementDto).
   */
  async create(establishmentId: string, userId: string, dto: CreateLossDto) {
    if (dto.id) {
      const existing = await this.prisma.loss.findFirst({ where: { id: dto.id, establishmentId } });
      if (existing) return existing;
    }

    const product = await this.prisma.product.findFirst({ where: { id: dto.productId, establishmentId } });
    if (!product) {
      throw new NotFoundException('Produit introuvable pour cet établissement');
    }

    let nextQuantity: number;
    try {
      nextQuantity = applyStockMovement(product.stockQuantity.toNumber(), { type: 'loss', quantity: dto.quantity });
    } catch (error) {
      throw new BadRequestException(error instanceof Error ? error.message : 'Perte invalide');
    }

    return this.prisma.$transaction(async (tx) => {
      await tx.product.update({ where: { id: product.id }, data: { stockQuantity: nextQuantity } });
      await tx.stockMovement.create({
        data: { productId: product.id, type: 'loss', quantity: dto.quantity, reason: dto.reason, createdBy: userId },
      });
      return tx.loss.create({
        data: { id: dto.id, establishmentId, productId: product.id, quantity: dto.quantity, reason: dto.reason, createdBy: userId },
      });
    });
  }

  async list(establishmentId: string) {
    const losses = await this.prisma.loss.findMany({
      where: { establishmentId },
      include: { product: { select: { name: true, purchasePrice: true } } },
      orderBy: { createdAt: 'desc' },
    });
    return losses.map((loss) => ({
      id: loss.id,
      productId: loss.productId,
      productName: loss.product.name,
      quantity: loss.quantity.toNumber(),
      reason: loss.reason,
      estimatedValue: loss.quantity.toNumber() * (loss.product.purchasePrice?.toNumber() ?? 0),
      createdAt: loss.createdAt,
    }));
  }
}
