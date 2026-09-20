import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import { ActivityNotifierService } from '../notifications/activity-notifier.service.js';
import { applyStockMovement } from '../stock/stock-math.js';
import type { CreateLossDto } from './dto/create-loss.dto.js';
import type { UpdateLossDto } from './dto/update-loss.dto.js';

/** `Loss` et son `StockMovement` 'loss' sont créés dans la même transaction (sans clé étrangère entre eux) : ils se retrouvent par produit/quantité/auteur et un horodatage à quelques secondes près. */
const MOVEMENT_MATCH_WINDOW_MS = 10_000;

/** Tolérance sur une date de perte saisie (fuseaux horaires) : au plus 24 h dans le futur. */
const MAX_FUTURE_MS = 24 * 60 * 60 * 1000;

@Injectable()
export class LossesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly activityNotifier: ActivityNotifierService,
  ) {}

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

    const createdAt = dto.createdAt ? new Date(dto.createdAt) : undefined;
    if (createdAt && createdAt.getTime() > Date.now() + MAX_FUTURE_MS) {
      throw new BadRequestException('La date de la perte ne peut pas être dans le futur');
    }

    let nextQuantity: number;
    try {
      nextQuantity = applyStockMovement(product.stockQuantity.toNumber(), { type: 'loss', quantity: dto.quantity });
    } catch (error) {
      throw new BadRequestException(error instanceof Error ? error.message : 'Perte invalide');
    }

    const loss = await this.prisma.$transaction(async (tx) => {
      await tx.product.update({ where: { id: product.id }, data: { stockQuantity: nextQuantity } });
      await tx.stockMovement.create({
        data: { productId: product.id, type: 'loss', quantity: dto.quantity, reason: dto.reason, createdBy: userId, createdAt },
      });
      return tx.loss.create({
        data: { id: dto.id, establishmentId, productId: product.id, quantity: dto.quantity, reason: dto.reason, createdBy: userId, createdAt },
      });
    });
    await this.activityNotifier.notify(
      establishmentId,
      userId,
      'Perte enregistrée',
      `${product.name} — ${dto.quantity}${dto.reason ? ` (${dto.reason})` : ''}`,
    );
    return loss;
  }

  private async findLossOrThrow(establishmentId: string, lossId: string) {
    const loss = await this.prisma.loss.findFirst({ where: { id: lossId, establishmentId } });
    if (!loss) {
      throw new NotFoundException('Perte introuvable pour cet établissement');
    }
    return loss;
  }

  private findLossMovement(
    tx: Pick<PrismaService, 'stockMovement'>,
    loss: { productId: string; quantity: { toNumber(): number }; createdBy: string | null; createdAt: Date },
  ) {
    return tx.stockMovement.findFirst({
      where: {
        productId: loss.productId,
        type: 'loss',
        quantity: loss.quantity.toNumber(),
        createdBy: loss.createdBy,
        createdAt: {
          gte: new Date(loss.createdAt.getTime() - MOVEMENT_MATCH_WINDOW_MS),
          lte: new Date(loss.createdAt.getTime() + MOVEMENT_MATCH_WINDOW_MS),
        },
      },
      orderBy: { createdAt: 'asc' },
    });
  }

  /**
   * Corrige date/produit/quantité/motif d'une perte (permission `losses.edit`,
   * Super Administrateur/Gérant/Serveur — demande utilisateur du 2026-09-20).
   * Le stock suit : l'ancienne quantité est restituée au produit d'origine,
   * la nouvelle est retirée du produit choisi (refusée si le stock est
   * insuffisant), et le mouvement de stock 'loss' associé est mis à jour pour
   * que Graphiques > Stock (lots FIFO) reste cohérent.
   */
  async update(establishmentId: string, userId: string, lossId: string, dto: UpdateLossDto) {
    const loss = await this.findLossOrThrow(establishmentId, lossId);
    const productId = dto.productId ?? loss.productId;
    const quantity = dto.quantity ?? loss.quantity.toNumber();
    const reason = dto.reason !== undefined ? dto.reason : loss.reason;
    const createdAt = dto.createdAt ? new Date(dto.createdAt) : loss.createdAt;

    const product = await this.prisma.product.findFirst({ where: { id: productId, establishmentId } });
    if (!product) {
      throw new NotFoundException('Produit introuvable pour cet établissement');
    }
    const sameProduct = productId === loss.productId;
    const oldProduct = sameProduct
      ? product
      : await this.prisma.product.findFirst({ where: { id: loss.productId, establishmentId } });
    if (!oldProduct) {
      throw new NotFoundException('Produit introuvable pour cet établissement');
    }

    let newStock: number;
    try {
      const base = sameProduct
        ? product.stockQuantity.toNumber() + loss.quantity.toNumber()
        : product.stockQuantity.toNumber();
      newStock = applyStockMovement(base, { type: 'loss', quantity });
    } catch (error) {
      throw new BadRequestException(error instanceof Error ? error.message : 'Perte invalide');
    }

    const updated = await this.prisma.$transaction(async (tx) => {
      const movement = await this.findLossMovement(tx, loss);
      if (!sameProduct) {
        await tx.product.update({
          where: { id: oldProduct.id },
          data: { stockQuantity: oldProduct.stockQuantity.toNumber() + loss.quantity.toNumber() },
        });
      }
      await tx.product.update({ where: { id: product.id }, data: { stockQuantity: newStock } });
      if (movement) {
        await tx.stockMovement.update({
          where: { id: movement.id },
          data: { productId: product.id, quantity, reason, createdAt },
        });
      } else {
        await tx.stockMovement.create({
          data: { productId: product.id, type: 'loss', quantity, reason, createdBy: userId, createdAt },
        });
      }
      return tx.loss.update({
        where: { id: lossId },
        data: { productId: product.id, quantity, reason, createdAt },
      });
    });
    await this.activityNotifier.notify(
      establishmentId,
      userId,
      'Perte modifiée',
      `${product.name} — ${quantity}${reason ? ` (${reason})` : ''}`,
    );
    return updated;
  }

  /** Supprime une perte et restitue sa quantité au stock du produit (permission `losses.edit`). */
  async remove(establishmentId: string, userId: string, lossId: string): Promise<void> {
    const loss = await this.findLossOrThrow(establishmentId, lossId);
    const product = await this.prisma.product.findFirst({ where: { id: loss.productId, establishmentId } });
    if (!product) {
      throw new NotFoundException('Produit introuvable pour cet établissement');
    }
    await this.prisma.$transaction(async (tx) => {
      const movement = await this.findLossMovement(tx, loss);
      await tx.product.update({
        where: { id: product.id },
        data: { stockQuantity: product.stockQuantity.toNumber() + loss.quantity.toNumber() },
      });
      if (movement) {
        await tx.stockMovement.delete({ where: { id: movement.id } });
      }
      await tx.loss.delete({ where: { id: lossId } });
    });
    await this.activityNotifier.notify(
      establishmentId,
      userId,
      'Perte supprimée',
      `${product.name} — ${loss.quantity.toNumber()}${loss.reason ? ` (${loss.reason})` : ''}`,
    );
  }

  async list(establishmentId: string) {
    const losses = await this.prisma.loss.findMany({
      where: { establishmentId },
      include: {
        product: { select: { name: true, salePrice: true, referenceSalePrice: true } },
        createdByUser: { select: { fullName: true } },
      },
      orderBy: { createdAt: 'desc' },
    });
    return losses.map((loss) => {
      // Prix de vente du produit (décision utilisateur du 2026-09-20, en
      // remplacement du prix d'achat) ; un produit dont le prix se saisit à
      // chaque vente (`salePrice` nul, ex. Gbêlê) retombe sur son prix de
      // vente de référence, sinon 0.
      const unitSalePrice = loss.product.salePrice?.toNumber() ?? loss.product.referenceSalePrice?.toNumber() ?? 0;
      return {
        id: loss.id,
        productId: loss.productId,
        productName: loss.product.name,
        quantity: loss.quantity.toNumber(),
        reason: loss.reason,
        unitSalePrice,
        estimatedValue: loss.quantity.toNumber() * unitSalePrice,
        createdByName: loss.createdByUser?.fullName ?? null,
        createdAt: loss.createdAt,
      };
    });
  }
}
