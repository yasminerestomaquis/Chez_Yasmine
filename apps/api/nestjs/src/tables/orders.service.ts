import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import type { AddOrderItemDto, SplitOrderDto, TransferOrderDto } from './dto/order-operations.dto.js';

@Injectable()
export class OrdersService {
  constructor(private readonly prisma: PrismaService) {}

  private async getOpenOrderOrThrow(establishmentId: string, orderId: string) {
    const order = await this.prisma.order.findFirst({ where: { id: orderId, establishmentId } });
    if (!order) {
      throw new NotFoundException('Addition introuvable pour cet établissement');
    }
    if (order.status !== 'open') {
      throw new ConflictException('Cette addition est déjà clôturée');
    }
    return order;
  }

  private async getFreeTableOrThrow(establishmentId: string, tableId: string) {
    const table = await this.prisma.restaurantTable.findFirst({ where: { id: tableId, establishmentId } });
    if (!table) {
      throw new BadRequestException("La table indiquée n'appartient pas à cet établissement");
    }
    if (table.status !== 'free') {
      throw new ConflictException('La table de destination est déjà occupée');
    }
    return table;
  }

  /** Only one open order per table is created through this endpoint — split() is the deliberate exception (see its docstring). */
  async openTable(establishmentId: string, tableId: string, serverId: string) {
    const table = await this.prisma.restaurantTable.findFirst({ where: { id: tableId, establishmentId } });
    if (!table) {
      throw new NotFoundException('Table introuvable pour cet établissement');
    }
    if (table.status !== 'free') {
      throw new ConflictException('Cette table est déjà occupée');
    }

    return this.prisma.$transaction(async (tx) => {
      const order = await tx.order.create({ data: { establishmentId, tableId, serverId, status: 'open' } });
      await tx.restaurantTable.update({ where: { id: tableId }, data: { status: 'occupied' } });
      return order;
    });
  }

  async getOpenOrderForTable(establishmentId: string, tableId: string) {
    const order = await this.prisma.order.findFirst({
      where: { establishmentId, tableId, status: 'open' },
      include: { items: { include: { product: { select: { name: true } } } } },
    });
    if (!order) {
      throw new NotFoundException('Aucune addition ouverte pour cette table');
    }
    return order;
  }

  async addItem(establishmentId: string, orderId: string, dto: AddOrderItemDto) {
    const order = await this.getOpenOrderOrThrow(establishmentId, orderId);
    const product = await this.prisma.product.findFirst({ where: { id: dto.productId, establishmentId } });
    if (!product) {
      throw new BadRequestException("Le produit indiqué n'appartient pas à cet établissement");
    }
    // Catégorie à prix variable (docs/api/catalog.md) : pas de prix fixe à
    // reprendre ici — les additions de table ne proposent pas encore de
    // saisie de prix (contrairement à la Caisse), donc ces produits ne
    // peuvent pas y être ajoutés pour l'instant.
    if (product.salePrice == null) {
      throw new BadRequestException(
        `${product.name} a un prix variable : ajoutez-le depuis la Caisse plutôt que depuis une addition de table`,
      );
    }
    return this.prisma.orderItem.create({
      data: { orderId: order.id, productId: product.id, quantity: dto.quantity, unitPrice: product.salePrice },
    });
  }

  async removeItem(establishmentId: string, orderId: string, itemId: string): Promise<void> {
    await this.getOpenOrderOrThrow(establishmentId, orderId);
    const { count } = await this.prisma.orderItem.deleteMany({ where: { id: itemId, orderId } });
    if (count === 0) {
      throw new NotFoundException('Article introuvable sur cette addition');
    }
  }

  async transfer(establishmentId: string, orderId: string, dto: TransferOrderDto) {
    const order = await this.getOpenOrderOrThrow(establishmentId, orderId);
    if (order.tableId === dto.toTableId) {
      throw new BadRequestException('La table de destination est identique à la table actuelle');
    }
    await this.getFreeTableOrThrow(establishmentId, dto.toTableId);

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.order.update({ where: { id: orderId }, data: { tableId: dto.toTableId } });
      await tx.restaurantTable.update({ where: { id: dto.toTableId }, data: { status: 'occupied' } });
      if (order.tableId) {
        await tx.restaurantTable.update({ where: { id: order.tableId }, data: { status: 'free' } });
      }
      return updated;
    });
  }

  /** Merges `orderId`'s items into `intoOrderId`, then closes `orderId` and frees its table. */
  async merge(establishmentId: string, orderId: string, intoOrderId: string) {
    if (orderId === intoOrderId) {
      throw new BadRequestException('Impossible de fusionner une addition avec elle-même');
    }
    const source = await this.getOpenOrderOrThrow(establishmentId, orderId);
    const target = await this.getOpenOrderOrThrow(establishmentId, intoOrderId);

    return this.prisma.$transaction(async (tx) => {
      await tx.orderItem.updateMany({ where: { orderId: source.id }, data: { orderId: target.id } });
      await tx.order.update({ where: { id: source.id }, data: { status: 'closed', closedAt: new Date() } });
      if (source.tableId) {
        await tx.restaurantTable.update({ where: { id: source.tableId }, data: { status: 'free' } });
      }
      return tx.order.findUniqueOrThrow({ where: { id: target.id }, include: { items: true } });
    });
  }

  /**
   * Splits selected items off `orderId` into a brand-new order on `toTableId`.
   * `toTableId` may be the *same* table (splitting a bill between two groups
   * still seated together) — in that case the table stays occupied and now
   * legitimately has two open orders, the one deliberate exception to "one
   * open order per table". A *different* target table must be free.
   */
  async split(establishmentId: string, orderId: string, dto: SplitOrderDto) {
    const source = await this.getOpenOrderOrThrow(establishmentId, orderId);
    const items = await this.prisma.orderItem.findMany({ where: { id: { in: dto.itemIds }, orderId } });
    if (items.length !== dto.itemIds.length) {
      throw new BadRequestException("Un ou plusieurs articles n'appartiennent pas à cette addition");
    }

    const isSameTable = dto.toTableId === source.tableId;
    if (!isSameTable) {
      await this.getFreeTableOrThrow(establishmentId, dto.toTableId);
    }

    return this.prisma.$transaction(async (tx) => {
      const newOrder = await tx.order.create({
        data: { establishmentId, tableId: dto.toTableId, serverId: source.serverId, status: 'open' },
      });
      await tx.orderItem.updateMany({ where: { id: { in: dto.itemIds } }, data: { orderId: newOrder.id } });
      if (!isSameTable) {
        await tx.restaurantTable.update({ where: { id: dto.toTableId }, data: { status: 'occupied' } });
      }
      return tx.order.findUniqueOrThrow({ where: { id: newOrder.id }, include: { items: true } });
    });
  }
}
