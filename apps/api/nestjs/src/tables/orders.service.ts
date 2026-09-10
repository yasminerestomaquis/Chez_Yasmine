import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import type { Prisma } from '@prisma/client';
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
  async openTable(establishmentId: string, tableId: string, serverId: string, guestCount?: number) {
    const table = await this.prisma.restaurantTable.findFirst({ where: { id: tableId, establishmentId } });
    if (!table) {
      throw new NotFoundException('Table introuvable pour cet établissement');
    }
    // Une table réservée peut être ouverte normalement (le client attendu
    // arrive) — voir ReservationsService, qui a posé ce statut.
    if (table.status !== 'free' && table.status !== 'reserved') {
      throw new ConflictException('Cette table est déjà occupée');
    }

    return this.prisma.$transaction(async (tx) => {
      const order = await tx.order.create({ data: { establishmentId, tableId, serverId, status: 'open', guestCount } });
      await tx.restaurantTable.update({ where: { id: tableId }, data: { status: 'occupied' } });
      if (table.status === 'reserved') {
        await tx.reservation.updateMany({ where: { tableId, status: 'pending' }, data: { status: 'seated' } });
      }
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

  /**
   * Un produit à prix fixe ignore tout `unitPrice` envoyé par le client (le
   * prix catalogue prévaut toujours, relu à chaque ajout). Un produit à prix
   * variable (Poulets, Poissons, Plats africains — `product.salePrice` nul)
   * exige `dto.unitPrice`, même règle que `SalesService.create` en Caisse.
   *
   * Fusion par ligne : si l'addition a déjà une ligne pour ce même produit AU
   * MÊME PRIX, sa quantité est incrémentée plutôt que de créer une nouvelle
   * ligne — aligné sur le comportement du panier local de la Caisse
   * (`PosPage._addToCart`). Deux prix différents pour un même produit à prix
   * variable restent deux lignes distinctes (deux pièces vendues à des prix
   * différents le même jour).
   */
  async addItem(establishmentId: string, orderId: string, dto: AddOrderItemDto) {
    const order = await this.getOpenOrderOrThrow(establishmentId, orderId);
    const product = await this.prisma.product.findFirst({ where: { id: dto.productId, establishmentId } });
    if (!product) {
      throw new BadRequestException("Le produit indiqué n'appartient pas à cet établissement");
    }

    // Reste en Decimal pour un produit à prix fixe (comme le faisait le code
    // original) ; converti en number seulement côté prix variable, où il
    // provient déjà de dto.unitPrice — évite de casser l'égalité stricte
    // attendue par les tests existants sur le type exact écrit en base.
    let unitPrice: number | Prisma.Decimal;
    if (product.salePrice != null) {
      unitPrice = product.salePrice;
    } else {
      if (dto.unitPrice == null) {
        throw new BadRequestException(`Prix de vente requis pour ${product.name} (catégorie à prix variable)`);
      }
      unitPrice = dto.unitPrice;
    }

    const existing = await this.prisma.orderItem.findFirst({
      where: { orderId: order.id, productId: product.id, unitPrice },
    });
    if (existing) {
      return this.prisma.orderItem.update({
        where: { id: existing.id },
        data: { quantity: existing.quantity.toNumber() + dto.quantity },
      });
    }
    return this.prisma.orderItem.create({
      data: { orderId: order.id, productId: product.id, quantity: dto.quantity, unitPrice },
    });
  }

  /** Modifie la quantité d'une ligne déjà présente sur l'addition — utilisé par le +/- du panier de l'écran de table. Pour supprimer une ligne, utiliser `removeItem` plutôt qu'une quantité à 0. */
  async updateItemQuantity(establishmentId: string, orderId: string, itemId: string, quantity: number) {
    await this.getOpenOrderOrThrow(establishmentId, orderId);
    const { count } = await this.prisma.orderItem.updateMany({
      where: { id: itemId, orderId },
      data: { quantity },
    });
    if (count === 0) {
      throw new NotFoundException('Article introuvable sur cette addition');
    }
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
