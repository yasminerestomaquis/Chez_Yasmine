import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import type { Prisma, Product } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service.js';
import type { AddOrderItemDto, SplitOrderDto, TransferOrderDto } from './dto/order-operations.dto.js';
import { resolveReferencePriceLine } from '../pos/reference-price.js';

/** Les quantités sont en Decimal(12,2) : comparaison à la précision de la base. */
function sameQuantity(a: number, b: number): boolean {
  return Math.abs(a - b) < 0.005;
}

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

  /**
   * Ouvre une addition supplémentaire sur une table DÉJÀ occupée — contrairement
   * à `openTable`, qui exige `'free'`/`'reserved'` et occupe la table. Le
   * statut de la table reste inchangé (déjà `occupied`). Utilisé par le bouton
   * « Nouvelle addition » de l'écran de table (décision utilisateur 2026-09-10,
   * voir docs/superpowers/specs/2026-09-10-table-order-caisse-design.md).
   */
  async openAdditionalOrder(establishmentId: string, tableId: string, serverId: string, guestCount?: number) {
    const table = await this.prisma.restaurantTable.findFirst({ where: { id: tableId, establishmentId } });
    if (!table) {
      throw new NotFoundException('Table introuvable pour cet établissement');
    }
    if (table.status !== 'occupied') {
      throw new ConflictException("Cette table n'est pas occupée — utilisez l'ouverture normale");
    }
    // `include: { items: true }` : une addition neuve n'a jamais d'article,
    // mais la réponse doit tout de même porter la clé `items` (même forme
    // que `listOpenOrdersForTable`) — sans elle, `OrderDetail.fromJson` côté
    // Flutter plante (`items` absent du JSON), aussi bien depuis
    // `floor_plan_page.dart` que `table_order_page.dart`.
    return this.prisma.order.create({
      data: { establishmentId, tableId, serverId, status: 'open', guestCount },
      include: { items: true },
    });
  }

  /**
   * Libère une table sans condition (décision utilisateur 2026-09-10) : un
   * client peut quitter une table sans payer, ou une table peut avoir été
   * ouverte par erreur. Toutes ses additions ouvertes passent au statut
   * `cancelled` (aucune vente, aucun impact stock/recettes, trace conservée
   * en base pour l'historique) ; la table repasse `free`. Idempotent —
   * aucune exception si la table n'a déjà aucune addition ouverte.
   */
  async release(establishmentId: string, tableId: string): Promise<void> {
    const table = await this.prisma.restaurantTable.findFirst({ where: { id: tableId, establishmentId } });
    if (!table) {
      throw new NotFoundException('Table introuvable pour cet établissement');
    }
    await this.prisma.$transaction(async (tx) => {
      await tx.order.updateMany({ where: { tableId, status: 'open' }, data: { status: 'cancelled', closedAt: new Date() } });
      await tx.restaurantTable.update({ where: { id: tableId }, data: { status: 'free' } });
    });
  }

  async listOpenOrdersForTable(establishmentId: string, tableId: string) {
    const orders = await this.prisma.order.findMany({
      where: { establishmentId, tableId, status: 'open' },
      orderBy: { openedAt: 'asc' },
      include: {
        items: {
          include: {
            product: {
              select: { name: true, referenceSalePrice: true, category: { select: { hasCasePricing: true, hasVariablePricing: true } } },
            },
          },
        },
      },
    });
    if (orders.length === 0) {
      throw new NotFoundException('Aucune addition ouverte pour cette table');
    }
    return orders;
  }

  /**
   * Prix et quantité d'une ligne d'addition à partir du produit et de la
   * demande — règles détaillées sur `addItem`, partagées avec
   * `addItemWithId` (saisie hors ligne).
   *
   * Reste en Decimal pour un produit à prix fixe (comme le faisait le code
   * original) ; converti en number pour tout autre cas — évite de casser
   * l'égalité stricte attendue par les tests existants sur le type exact
   * écrit en base.
   */
  private resolveLine(
    product: Product,
    dto: AddOrderItemDto,
  ): { unitPrice: number | Prisma.Decimal; quantity: number; sellAsUnit: boolean } {
    if (product.salePrice != null) {
      let unitPrice: number | Prisma.Decimal = product.salePrice;
      let sellAsUnit = false;
      if (dto.sellAsUnit && product.unitSalePrice != null) {
        unitPrice = product.unitSalePrice;
        sellAsUnit = true;
      }
      if (dto.quantity == null) {
        throw new BadRequestException(`Quantité requise pour ${product.name}`);
      }
      return { unitPrice, quantity: dto.quantity, sellAsUnit };
    }
    if (product.referenceSalePrice != null) {
      // Prix de référence variable (ex. Gbêlê) : le serveur déduit quantité
      // et prix unitaire du montant payé — même principe que
      // `SalesService.create` en Caisse (décision utilisateur du 2026-09-24).
      if (dto.amountPaid == null) {
        throw new BadRequestException(`Montant payé requis pour ${product.name} (prix de référence variable)`);
      }
      const resolved = resolveReferencePriceLine(product.referenceSalePrice.toNumber(), dto.amountPaid, product.name);
      return { unitPrice: resolved.unitPrice, quantity: resolved.quantity, sellAsUnit: false };
    }
    if (dto.unitPrice == null || dto.quantity == null) {
      throw new BadRequestException(`Prix de vente et quantité requis pour ${product.name} (catégorie à prix variable)`);
    }
    return { unitPrice: dto.unitPrice, quantity: dto.quantity, sellAsUnit: false };
  }

  /**
   * Un produit à prix fixe ignore tout `unitPrice` envoyé par le client (le
   * prix catalogue prévaut toujours, relu à chaque ajout). Un produit à prix
   * variable (Poulets, Poissons, Plats africains — `product.salePrice` nul)
   * exige `dto.unitPrice`, même règle que `SalesService.create` en Caisse.
   * `dto.sellAsUnit` : même principe que `CreateSaleDto.items[].sellAsUnit`
   * en Caisse — utilise `product.unitSalePrice` au lieu de `product.salePrice`
   * quand le produit en a un (ex. Heineken 33/Despé 33). Mémorisé sur la
   * ligne (`OrderItem.sellAsUnit`) pour que le checkout de l'addition
   * applique la même tarification à la vente finale.
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

    const { unitPrice, quantity, sellAsUnit } = this.resolveLine(product, dto);

    const existing = await this.prisma.orderItem.findFirst({
      where: { orderId: order.id, productId: product.id, unitPrice },
    });
    if (existing) {
      return this.prisma.orderItem.update({
        where: { id: existing.id },
        data: { quantity: existing.quantity.toNumber() + quantity },
      });
    }
    return this.prisma.orderItem.create({
      data: { orderId: order.id, productId: product.id, quantity, unitPrice, sellAsUnit },
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

  // ── Saisie hors ligne (phase 4, voir docs/api/sync.md) ───────────────────
  //
  // Les opérations ci-dessous sont rejouées par `SyncService` depuis la file
  // d'attente d'un appareil qui a ouvert une table ou modifié une addition
  // sans réseau. Chacune est IDEMPOTENTE (un rejeu ne double jamais l'effet)
  // et les écritures de quantité refusent explicitement un conflit plutôt que
  // de laisser « le dernier écrit gagner » (prompt maître §28).

  /**
   * Ouvre une addition dont l'identifiant a été choisi par l'appareil.
   * Contrairement à `openTable`, ne refuse jamais une table déjà occupée : un
   * autre appareil a pu l'ouvrir entre-temps, et l'addition saisie hors ligne
   * devient alors simplement une addition supplémentaire (comme « Nouvelle
   * addition »), sans perdre ce qui a été saisi. Une table libre ou réservée
   * passe à `occupied`.
   */
  async openOfflineOrder(
    establishmentId: string,
    serverId: string,
    input: { id: string; tableId: string; guestCount?: number },
    openedAt?: Date,
  ) {
    const existing = await this.prisma.order.findFirst({
      where: { id: input.id, establishmentId },
      include: { items: true },
    });
    if (existing) return existing;

    const table = await this.prisma.restaurantTable.findFirst({ where: { id: input.tableId, establishmentId } });
    if (!table) {
      throw new NotFoundException('Table introuvable pour cet établissement');
    }
    return this.prisma.$transaction(async (tx) => {
      const order = await tx.order.create({
        data: {
          id: input.id,
          establishmentId,
          tableId: input.tableId,
          serverId,
          status: 'open',
          guestCount: input.guestCount,
          openedAt,
        },
        include: { items: true },
      });
      if (table.status === 'free' || table.status === 'reserved') {
        await tx.restaurantTable.update({ where: { id: input.tableId }, data: { status: 'occupied' } });
        if (table.status === 'reserved') {
          await tx.reservation.updateMany({ where: { tableId: input.tableId, status: 'pending' }, data: { status: 'seated' } });
        }
      }
      return order;
    });
  }

  /**
   * Comme `addItem`, avec l'identifiant de ligne choisi par l'appareil, et SANS
   * fusion avec une ligne existante (la fusion est faite côté appareil, par
   * une écriture de quantité) : c'est ce qui rend l'ajout idempotent — une
   * ligne dont l'identifiant existe déjà est simplement renvoyée.
   */
  async addItemWithId(establishmentId: string, orderId: string, itemId: string, dto: AddOrderItemDto) {
    const already = await this.prisma.orderItem.findFirst({ where: { id: itemId, orderId } });
    if (already) return already;

    const order = await this.getOpenOrderOrThrow(establishmentId, orderId);
    const product = await this.prisma.product.findFirst({ where: { id: dto.productId, establishmentId } });
    if (!product) {
      throw new BadRequestException("Le produit indiqué n'appartient pas à cet établissement");
    }
    const { unitPrice, quantity, sellAsUnit } = this.resolveLine(product, dto);
    return this.prisma.orderItem.create({
      data: { id: itemId, orderId: order.id, productId: product.id, quantity, unitPrice, sellAsUnit },
    });
  }

  /**
   * Fixe la quantité d'une ligne à `quantity`, sachant que l'appareil l'a vue à
   * `expectedQuantity`. Déjà à la valeur visée : rien à faire (rejeu). À une
   * autre valeur que celle vue par l'appareil : un autre appareil l'a modifiée
   * entre-temps — conflit explicite, jamais écrasé en silence.
   */
  async setItemQuantityIfExpected(
    establishmentId: string,
    orderId: string,
    itemId: string,
    expectedQuantity: number,
    quantity: number,
  ) {
    await this.getOpenOrderOrThrow(establishmentId, orderId);
    const item = await this.prisma.orderItem.findFirst({ where: { id: itemId, orderId } });
    if (!item) {
      throw new NotFoundException('Article introuvable sur cette addition');
    }
    const current = item.quantity.toNumber();
    if (sameQuantity(current, quantity)) return item;
    if (!sameQuantity(current, expectedQuantity)) {
      throw new ConflictException(
        `La quantité de cet article a été modifiée entre-temps (${current} au lieu de ${expectedQuantity})`,
      );
    }
    return this.prisma.orderItem.update({ where: { id: item.id }, data: { quantity } });
  }

  /**
   * Retire une ligne vue à `expectedQuantity` par l'appareil. Ligne déjà
   * absente : rien à faire (rejeu, ou retrait fait depuis un autre appareil).
   * Quantité différente de celle vue : conflit explicite — quelqu'un en a
   * ajouté depuis, on ne supprime pas ce que l'appareil n'a pas vu.
   */
  async removeItemIfExpected(establishmentId: string, orderId: string, itemId: string, expectedQuantity: number) {
    await this.getOpenOrderOrThrow(establishmentId, orderId);
    const item = await this.prisma.orderItem.findFirst({ where: { id: itemId, orderId } });
    if (!item) return { removed: false };
    const current = item.quantity.toNumber();
    if (!sameQuantity(current, expectedQuantity)) {
      throw new ConflictException(
        `La quantité de cet article a été modifiée entre-temps (${current} au lieu de ${expectedQuantity}) : retrait refusé`,
      );
    }
    await this.prisma.orderItem.delete({ where: { id: item.id } });
    return { removed: true };
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
