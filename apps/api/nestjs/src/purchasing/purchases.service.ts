import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import type { CreatePurchaseDto } from './dto/create-purchase.dto.js';

@Injectable()
export class PurchasesService {
  constructor(private readonly prisma: PrismaService) {}

  list(establishmentId: string) {
    return this.prisma.purchase.findMany({
      where: { establishmentId },
      include: { items: true, supplier: true },
      orderBy: { createdAt: 'desc' },
    });
  }

  async get(establishmentId: string, purchaseId: string) {
    const purchase = await this.prisma.purchase.findFirst({
      where: { id: purchaseId, establishmentId },
      include: { items: true, supplier: true },
    });
    if (!purchase) {
      throw new NotFoundException('Achat introuvable pour cet établissement');
    }
    return purchase;
  }

  async create(establishmentId: string, dto: CreatePurchaseDto) {
    if (dto.supplierId) {
      const supplier = await this.prisma.supplier.findFirst({ where: { id: dto.supplierId, establishmentId } });
      if (!supplier) {
        throw new BadRequestException("Le fournisseur indiqué n'appartient pas à cet établissement");
      }
    }
    const productIds = [...new Set(dto.items.map((i) => i.productId))];
    const products = await this.prisma.product.findMany({ where: { id: { in: productIds }, establishmentId } });
    if (products.length !== productIds.length) {
      throw new BadRequestException("Un ou plusieurs produits n'appartiennent pas à cet établissement");
    }

    const total = dto.items.reduce((sum, item) => sum + item.quantity * item.unitPrice, 0);
    return this.prisma.purchase.create({
      data: {
        establishmentId,
        supplierId: dto.supplierId,
        status: 'pending',
        total,
        items: { create: dto.items.map((item) => ({ productId: item.productId, quantity: item.quantity, unitPrice: item.unitPrice })) },
      },
      include: { items: true, supplier: true },
    });
  }

  /** Receiving a purchase is what actually moves stock — creating it never does (prompt maître §33 : les entrées de stock viennent de la réception, pas de la commande). */
  async receive(establishmentId: string, purchaseId: string, userId: string) {
    const purchase = await this.prisma.purchase.findFirst({
      where: { id: purchaseId, establishmentId },
      include: { items: true },
    });
    if (!purchase) {
      throw new NotFoundException('Achat introuvable pour cet établissement');
    }
    if (purchase.status !== 'pending') {
      throw new ConflictException('Cet achat a déjà été reçu ou annulé');
    }

    return this.prisma.$transaction(async (tx) => {
      for (const item of purchase.items) {
        const quantity = item.quantity.toNumber();
        await tx.product.update({ where: { id: item.productId }, data: { stockQuantity: { increment: quantity } } });
        await tx.stockMovement.create({
          data: { productId: item.productId, type: 'in', quantity, reason: `Réception achat ${purchase.id}`, createdBy: userId },
        });
      }
      return tx.purchase.update({
        where: { id: purchaseId },
        data: { status: 'received' },
        include: { items: true, supplier: true },
      });
    });
  }

  async cancel(establishmentId: string, purchaseId: string) {
    const purchase = await this.prisma.purchase.findFirst({ where: { id: purchaseId, establishmentId } });
    if (!purchase) {
      throw new NotFoundException('Achat introuvable pour cet établissement');
    }
    if (purchase.status !== 'pending') {
      throw new ConflictException('Seul un achat en attente peut être annulé');
    }
    return this.prisma.purchase.update({ where: { id: purchaseId }, data: { status: 'cancelled' } });
  }
}
