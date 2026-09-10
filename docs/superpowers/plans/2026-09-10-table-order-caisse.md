# Tables — libération sans condition, multi-additions, écran Caisse-table — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permettre de libérer une table occupée sans condition, gérer plusieurs additions simultanées sur une même table, et remplacer l'écran d'addition actuel (liste plate) par une interface reprenant la grille produits + panier de la Caisse.

**Architecture:** Backend NestJS — quatre nouvelles méthodes sur `OrdersService` (addition supplémentaire, liste des additions ouvertes, libération forcée, modification de quantité), deux corrections de bugs latents (`SalesService`/`TablesService`). Frontend Flutter — extraction de la grille produits et du panier de `pos_page.dart` en composants partagés (`lib/pos/product_grid.dart`, `lib/pos/cart_panel.dart`), nouvel écran `table_order_page.dart` à onglets qui les réutilise avec persistance serveur immédiate (au lieu du panier local de la Caisse), refonte des menus de `floor_plan_page.dart`.

**Tech Stack:** NestJS + Prisma (Postgres, `status` en texte libre, aucune migration requise), Flutter Web, vitest (backend), flutter_test (frontend).

**Spec de référence :** [`docs/superpowers/specs/2026-09-10-table-order-caisse-design.md`](../specs/2026-09-10-table-order-caisse-design.md)

---

## Task 1 : DTOs — `unitPrice` sur l'ajout d'article, nouveau DTO de modification de quantité

**Files:**
- Modify: `apps/api/nestjs/src/tables/dto/order-operations.dto.ts`

- [ ] **Step 1 : Ajouter `unitPrice` à `AddOrderItemDto` et créer `UpdateOrderItemDto`**

Remplacer le contenu du fichier par :

```typescript
import { ArrayMinSize, IsArray, IsInt, IsNumber, IsOptional, IsUUID, Min } from 'class-validator';

export class OpenTableDto {
  @IsOptional()
  @IsInt()
  @Min(1)
  guestCount?: number;
}

export class AddOrderItemDto {
  @IsUUID()
  productId!: string;

  @IsNumber()
  @Min(0.01)
  quantity!: number;

  /** Requis si le produit appartient à une catégorie à prix variable (Poulets, Poissons, Plats africains) — voir OrdersService.addItem. Ignoré pour un produit à prix fixe (le prix catalogue prévaut toujours). */
  @IsOptional()
  @IsNumber()
  @Min(0.01)
  unitPrice?: number;
}

export class UpdateOrderItemDto {
  @IsNumber()
  @Min(0.01)
  quantity!: number;
}

export class TransferOrderDto {
  @IsUUID()
  toTableId!: string;
}

export class MergeOrderDto {
  @IsUUID()
  intoOrderId!: string;
}

export class SplitOrderDto {
  @IsArray()
  @ArrayMinSize(1)
  @IsUUID('4', { each: true })
  itemIds!: string[];

  @IsUUID()
  toTableId!: string;
}
```

- [ ] **Step 2 : Commit**

```bash
git add apps/api/nestjs/src/tables/dto/order-operations.dto.ts
git commit -m "$(cat <<'EOF'
feat(tables): unitPrice optionnel sur AddOrderItemDto, nouveau UpdateOrderItemDto

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2 : `OrdersService.addItem` — accepter les produits à prix variable, fusionner les lignes identiques

**Files:**
- Modify: `apps/api/nestjs/src/tables/orders.service.ts:64-82`
- Test: `apps/api/nestjs/src/tables/orders.service.spec.ts:76-120`

- [ ] **Step 1 : Écrire les tests qui échouent**

Dans `orders.service.spec.ts`, remplacer l'ancien test `'rejects a variable-pricing product (ex. Poulets, Poissons, Plats africains) — no price entry here yet'` (lignes 111-119, qui décrit le comportement qu'on remplace) par ces trois tests :

```typescript
  it('accepts a variable-pricing product when a unit price is supplied, and looks up the existing line at that exact price', async () => {
    // Un produit à prix variable peut avoir plusieurs lignes à des prix
    // différents (deux pièces vendues à des prix différents le même jour) —
    // la recherche de fusion doit filtrer par unitPrice, pas seulement par
    // productId, sinon une nouvelle ligne à 2000 fusionnerait à tort avec une
    // éventuelle ligne existante à un autre prix.
    (prisma.order as any).findFirst.mockResolvedValue({ id: 'order-1', status: 'open' });
    (prisma.product as any).findFirst.mockResolvedValue({ id: 'p1', name: 'Poulet braisé', salePrice: null });
    (prisma.orderItem as any).findFirst.mockResolvedValue(null);

    await service.addItem('est-1', 'order-1', { productId: 'p1', quantity: 1, unitPrice: 2000 });

    expect(prisma.orderItem.findFirst).toHaveBeenCalledWith({
      where: { orderId: 'order-1', productId: 'p1', unitPrice: 2000 },
    });
    expect(prisma.orderItem.create).toHaveBeenCalledWith({
      data: { orderId: 'order-1', productId: 'p1', quantity: 1, unitPrice: 2000 },
    });
  });

  it('rejects a variable-pricing product without a unit price', async () => {
    (prisma.order as any).findFirst.mockResolvedValue({ id: 'order-1', status: 'open' });
    (prisma.product as any).findFirst.mockResolvedValue({ id: 'p1', name: 'Poulet braisé', salePrice: null });

    await expect(service.addItem('est-1', 'order-1', { productId: 'p1', quantity: 1 })).rejects.toBeInstanceOf(
      BadRequestException,
    );
    expect(prisma.orderItem.create).not.toHaveBeenCalled();
  });

  it('merges into the existing line when the same product at the same price is already on the order', async () => {
    (prisma.order as any).findFirst.mockResolvedValue({ id: 'order-1', status: 'open' });
    (prisma.product as any).findFirst.mockResolvedValue({ id: 'p1', salePrice: new Decimal(1500) });
    (prisma.orderItem as any).findFirst.mockResolvedValue({ id: 'item-1', quantity: new Decimal(2), unitPrice: new Decimal(1500) });

    await service.addItem('est-1', 'order-1', { productId: 'p1', quantity: 1 });

    expect(prisma.orderItem.update).toHaveBeenCalledWith({ where: { id: 'item-1' }, data: { quantity: 3 } });
    expect(prisma.orderItem.create).not.toHaveBeenCalled();
  });
```

Dans `makePrismaMock()` (lignes 7-17), ajouter `findFirst: vi.fn(), update: vi.fn()` à l'entrée `orderItem` :

```typescript
    orderItem: { create: vi.fn(), deleteMany: vi.fn(), findMany: vi.fn(), updateMany: vi.fn(), findFirst: vi.fn(), update: vi.fn() },
```

- [ ] **Step 2 : Lancer les tests pour vérifier qu'ils échouent**

Run: `cd apps/api/nestjs && npx vitest run src/tables/orders.service.spec.ts`
Expected: FAIL — `addItem` rejette encore systématiquement les produits à prix variable, et ne fusionne aucune ligne.

- [ ] **Step 3 : Implémenter**

Remplacer la méthode `addItem` (lignes 64-82 de `orders.service.ts`) par :

```typescript
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

    let unitPrice: number;
    if (product.salePrice != null) {
      unitPrice = product.salePrice.toNumber();
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
```

Vérifier que `AddOrderItemDto` est bien importé en haut du fichier (déjà le cas via le `type { AddOrderItemDto, SplitOrderDto, TransferOrderDto }` existant).

- [ ] **Step 4 : Lancer les tests pour vérifier qu'ils passent**

Run: `cd apps/api/nestjs && npx vitest run src/tables/orders.service.spec.ts`
Expected: PASS — tous les tests de `describe('OrdersService.addItem', ...)`.

- [ ] **Step 5 : Commit**

```bash
git add apps/api/nestjs/src/tables/orders.service.ts apps/api/nestjs/src/tables/orders.service.spec.ts
git commit -m "$(cat <<'EOF'
feat(tables): addItem accepte les produits à prix variable, fusionne les lignes identiques

Aligné sur PosPage._addToCart : même produit + même prix incrémente la
ligne existante plutôt que d'en créer une nouvelle.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3 : `OrdersService.updateItemQuantity` — modifier la quantité d'une ligne existante

**Files:**
- Modify: `apps/api/nestjs/src/tables/orders.service.ts` (nouvelle méthode, après `addItem`)
- Test: `apps/api/nestjs/src/tables/orders.service.spec.ts` (nouveau `describe`)

- [ ] **Step 1 : Écrire les tests qui échouent**

Ajouter dans `orders.service.spec.ts`, après le `describe('OrdersService.addItem', ...)` :

```typescript
describe('OrdersService.updateItemQuantity', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: OrdersService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new OrdersService(prisma as unknown as PrismaService);
  });

  it('rejects updating an item on a closed order', async () => {
    (prisma.order as any).findFirst.mockResolvedValue({ id: 'order-1', status: 'closed' });
    await expect(service.updateItemQuantity('est-1', 'order-1', 'item-1', 3)).rejects.toBeInstanceOf(ConflictException);
  });

  it('throws NotFoundException when the item does not belong to the order', async () => {
    (prisma.order as any).findFirst.mockResolvedValue({ id: 'order-1', status: 'open' });
    (prisma.orderItem as any).updateMany.mockResolvedValue({ count: 0 });
    await expect(service.updateItemQuantity('est-1', 'order-1', 'item-x', 3)).rejects.toBeInstanceOf(NotFoundException);
  });

  it('updates the quantity of an existing line', async () => {
    (prisma.order as any).findFirst.mockResolvedValue({ id: 'order-1', status: 'open' });
    (prisma.orderItem as any).updateMany.mockResolvedValue({ count: 1 });

    await service.updateItemQuantity('est-1', 'order-1', 'item-1', 5);

    expect(prisma.orderItem.updateMany).toHaveBeenCalledWith({
      where: { id: 'item-1', orderId: 'order-1' },
      data: { quantity: 5 },
    });
  });
});
```

- [ ] **Step 2 : Lancer les tests pour vérifier qu'ils échouent**

Run: `cd apps/api/nestjs && npx vitest run src/tables/orders.service.spec.ts`
Expected: FAIL — `service.updateItemQuantity` n'existe pas encore (`TypeError`).

- [ ] **Step 3 : Implémenter**

Ajouter dans `orders.service.ts`, juste après la méthode `addItem` :

```typescript
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
```

- [ ] **Step 4 : Lancer les tests pour vérifier qu'ils passent**

Run: `cd apps/api/nestjs && npx vitest run src/tables/orders.service.spec.ts`
Expected: PASS.

- [ ] **Step 5 : Commit**

```bash
git add apps/api/nestjs/src/tables/orders.service.ts apps/api/nestjs/src/tables/orders.service.spec.ts
git commit -m "$(cat <<'EOF'
feat(tables): OrdersService.updateItemQuantity

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4 : `OrdersService.openAdditionalOrder` — ouvrir une addition supplémentaire sur une table occupée

**Files:**
- Modify: `apps/api/nestjs/src/tables/orders.service.ts` (nouvelle méthode, après `openTable`)
- Test: `apps/api/nestjs/src/tables/orders.service.spec.ts` (nouveau `describe`)

- [ ] **Step 1 : Écrire les tests qui échouent**

Ajouter dans `orders.service.spec.ts`, après le `describe('OrdersService.openTable', ...)` :

```typescript
describe('OrdersService.openAdditionalOrder', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: OrdersService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new OrdersService(prisma as unknown as PrismaService);
  });

  it('throws NotFoundException for a table outside the establishment', async () => {
    (prisma.restaurantTable as any).findFirst.mockResolvedValue(null);
    await expect(service.openAdditionalOrder('est-1', 'table-x', 'user-1')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('rejects opening an additional order on a table that is not occupied', async () => {
    (prisma.restaurantTable as any).findFirst.mockResolvedValue({ id: 't1', status: 'free' });
    await expect(service.openAdditionalOrder('est-1', 't1', 'user-1')).rejects.toBeInstanceOf(ConflictException);
  });

  it('creates a new open order without touching the table status', async () => {
    (prisma.restaurantTable as any).findFirst.mockResolvedValue({ id: 't1', status: 'occupied' });
    (prisma.order as any).create.mockResolvedValue({ id: 'order-2' });

    await service.openAdditionalOrder('est-1', 't1', 'user-1', 2);

    expect(prisma.order.create).toHaveBeenCalledWith({
      data: { establishmentId: 'est-1', tableId: 't1', serverId: 'user-1', status: 'open', guestCount: 2 },
    });
    expect(prisma.restaurantTable.update).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2 : Lancer les tests pour vérifier qu'ils échouent**

Run: `cd apps/api/nestjs && npx vitest run src/tables/orders.service.spec.ts`
Expected: FAIL — `service.openAdditionalOrder` n'existe pas encore.

- [ ] **Step 3 : Implémenter**

Ajouter dans `orders.service.ts`, juste après la méthode `openTable` (avant `getOpenOrderForTable`) :

```typescript
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
    return this.prisma.order.create({ data: { establishmentId, tableId, serverId, status: 'open', guestCount } });
  }
```

- [ ] **Step 4 : Lancer les tests pour vérifier qu'ils passent**

Run: `cd apps/api/nestjs && npx vitest run src/tables/orders.service.spec.ts`
Expected: PASS.

- [ ] **Step 5 : Commit**

```bash
git add apps/api/nestjs/src/tables/orders.service.ts apps/api/nestjs/src/tables/orders.service.spec.ts
git commit -m "$(cat <<'EOF'
feat(tables): OrdersService.openAdditionalOrder

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5 : `OrdersService.listOpenOrdersForTable` — remplace `getOpenOrderForTable`

**Files:**
- Modify: `apps/api/nestjs/src/tables/orders.service.ts:53-62`
- Test: `apps/api/nestjs/src/tables/orders.service.spec.ts` (nouveau `describe`)

- [ ] **Step 1 : Écrire les tests qui échouent**

Ajouter dans `orders.service.spec.ts` :

```typescript
describe('OrdersService.listOpenOrdersForTable', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: OrdersService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new OrdersService(prisma as unknown as PrismaService);
  });

  it('throws NotFoundException when the table has no open order', async () => {
    (prisma.order as any).findMany.mockResolvedValue([]);
    await expect(service.listOpenOrdersForTable('est-1', 't1')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('returns every open order for the table, each with its items', async () => {
    (prisma.order as any).findMany.mockResolvedValue([{ id: 'order-1' }, { id: 'order-2' }]);

    const result = await service.listOpenOrdersForTable('est-1', 't1');

    expect(result).toEqual([{ id: 'order-1' }, { id: 'order-2' }]);
    expect(prisma.order.findMany).toHaveBeenCalledWith({
      where: { establishmentId: 'est-1', tableId: 't1', status: 'open' },
      orderBy: { openedAt: 'asc' },
      include: { items: { include: { product: { select: { name: true } } } } },
    });
  });
});
```

Ajouter `findMany: vi.fn()` à l'entrée `order` de `makePrismaMock()` (ligne 9) :

```typescript
    order: { create: vi.fn(), findFirst: vi.fn(), findMany: vi.fn(), update: vi.fn(), findUniqueOrThrow: vi.fn() },
```

- [ ] **Step 2 : Lancer les tests pour vérifier qu'ils échouent**

Run: `cd apps/api/nestjs && npx vitest run src/tables/orders.service.spec.ts`
Expected: FAIL — `service.listOpenOrdersForTable` n'existe pas encore.

- [ ] **Step 3 : Implémenter**

Remplacer la méthode `getOpenOrderForTable` (lignes 53-62) par :

```typescript
  async listOpenOrdersForTable(establishmentId: string, tableId: string) {
    const orders = await this.prisma.order.findMany({
      where: { establishmentId, tableId, status: 'open' },
      orderBy: { openedAt: 'asc' },
      include: { items: { include: { product: { select: { name: true } } } } },
    });
    if (orders.length === 0) {
      throw new NotFoundException('Aucune addition ouverte pour cette table');
    }
    return orders;
  }
```

- [ ] **Step 4 : Mettre à jour le contrôleur**

Dans `orders.controller.ts`, remplacer la méthode `getOpenOrderForTable` (lignes 25-28) par :

```typescript
  @Get('tables/:tableId/orders')
  listOpenOrdersForTable(@Param('establishmentId') establishmentId: string, @Param('tableId') tableId: string) {
    return this.orders.listOpenOrdersForTable(establishmentId, tableId);
  }
```

- [ ] **Step 5 : Lancer les tests pour vérifier qu'ils passent**

Run: `cd apps/api/nestjs && npx vitest run src/tables/orders.service.spec.ts`
Expected: PASS.

- [ ] **Step 6 : Commit**

```bash
git add apps/api/nestjs/src/tables/orders.service.ts apps/api/nestjs/src/tables/orders.service.spec.ts apps/api/nestjs/src/tables/orders.controller.ts
git commit -m "$(cat <<'EOF'
feat(tables): GET tables/:tableId/orders liste toutes les additions ouvertes

Remplace GET tables/:tableId/order (findFirst, une seule addition) —
nécessaire pour le multi-addition par table.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6 : `OrdersService.release` — libérer une table sans condition

**Files:**
- Modify: `apps/api/nestjs/src/tables/orders.service.ts` (nouvelle méthode)
- Test: `apps/api/nestjs/src/tables/orders.service.spec.ts` (nouveau `describe`)

- [ ] **Step 1 : Écrire les tests qui échouent**

Ajouter dans `orders.service.spec.ts` :

```typescript
describe('OrdersService.release', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: OrdersService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new OrdersService(prisma as unknown as PrismaService);
  });

  it('throws NotFoundException for a table outside the establishment', async () => {
    (prisma.restaurantTable as any).findFirst.mockResolvedValue(null);
    await expect(service.release('est-1', 'table-x')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('cancels every open order and frees the table, unconditionally', async () => {
    (prisma.restaurantTable as any).findFirst.mockResolvedValue({ id: 't1', status: 'occupied' });
    (prisma.order as any).updateMany.mockResolvedValue({ count: 2 });

    await service.release('est-1', 't1');

    expect(prisma.order.updateMany).toHaveBeenCalledWith({
      where: { tableId: 't1', status: 'open' },
      data: { status: 'cancelled', closedAt: expect.any(Date) },
    });
    expect(prisma.restaurantTable.update).toHaveBeenCalledWith({ where: { id: 't1' }, data: { status: 'free' } });
  });

  it('is idempotent when the table has no open order', async () => {
    (prisma.restaurantTable as any).findFirst.mockResolvedValue({ id: 't1', status: 'occupied' });
    (prisma.order as any).updateMany.mockResolvedValue({ count: 0 });

    await expect(service.release('est-1', 't1')).resolves.toBeUndefined();
    expect(prisma.restaurantTable.update).toHaveBeenCalledWith({ where: { id: 't1' }, data: { status: 'free' } });
  });
});
```

Ajouter `updateMany: vi.fn()` à l'entrée `order` de `makePrismaMock()` :

```typescript
    order: { create: vi.fn(), findFirst: vi.fn(), findMany: vi.fn(), update: vi.fn(), updateMany: vi.fn(), findUniqueOrThrow: vi.fn() },
```

- [ ] **Step 2 : Lancer les tests pour vérifier qu'ils échouent**

Run: `cd apps/api/nestjs && npx vitest run src/tables/orders.service.spec.ts`
Expected: FAIL — `service.release` n'existe pas encore.

- [ ] **Step 3 : Implémenter**

Ajouter dans `orders.service.ts`, juste après `openAdditionalOrder` :

```typescript
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
```

- [ ] **Step 4 : Lancer les tests pour vérifier qu'ils passent**

Run: `cd apps/api/nestjs && npx vitest run src/tables/orders.service.spec.ts`
Expected: PASS.

- [ ] **Step 5 : Commit**

```bash
git add apps/api/nestjs/src/tables/orders.service.ts apps/api/nestjs/src/tables/orders.service.spec.ts
git commit -m "$(cat <<'EOF'
feat(tables): OrdersService.release — libération d'une table sans condition

Annule toutes les additions ouvertes (statut 'cancelled', aucun impact
stock/recettes) et libère la table, sans confirmation ni vérification de
contenu (décision utilisateur 2026-09-10).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7 : Contrôleur — routes `additions`, `release`, `PATCH items`

**Files:**
- Modify: `apps/api/nestjs/src/tables/orders.controller.ts`

- [ ] **Step 1 : Ajouter les trois routes**

Dans `orders.controller.ts`, ajouter `Patch` à l'import de `@nestjs/common` (ligne 1) :

```typescript
import { Body, Controller, Delete, Get, Param, Patch, Post, Req, UseGuards } from '@nestjs/common';
```

Étendre l'import des DTOs (ligne 6) :

```typescript
import {
  AddOrderItemDto,
  MergeOrderDto,
  OpenTableDto,
  SplitOrderDto,
  TransferOrderDto,
  UpdateOrderItemDto,
} from './dto/order-operations.dto.js';
```

Ajouter ces trois méthodes, juste après `openTable` (après la ligne 23) :

```typescript
  @Post('tables/:tableId/additions')
  openAdditionalOrder(
    @Req() request: Request,
    @Param('establishmentId') establishmentId: string,
    @Param('tableId') tableId: string,
    @Body() dto: OpenTableDto,
  ) {
    return this.orders.openAdditionalOrder(establishmentId, tableId, request.user!.sub, dto.guestCount);
  }

  @Post('tables/:tableId/release')
  release(@Param('establishmentId') establishmentId: string, @Param('tableId') tableId: string) {
    return this.orders.release(establishmentId, tableId);
  }
```

Ajouter la route `PATCH` juste après `addItem` (après la ligne 37) :

```typescript
  @Patch('orders/:orderId/items/:itemId')
  updateItem(
    @Param('establishmentId') establishmentId: string,
    @Param('orderId') orderId: string,
    @Param('itemId') itemId: string,
    @Body() dto: UpdateOrderItemDto,
  ) {
    return this.orders.updateItemQuantity(establishmentId, orderId, itemId, dto.quantity);
  }
```

- [ ] **Step 2 : Vérifier la compilation**

Run: `cd apps/api/nestjs && npm run build`
Expected: succès, aucune erreur TypeScript.

- [ ] **Step 3 : Commit**

```bash
git add apps/api/nestjs/src/tables/orders.controller.ts
git commit -m "$(cat <<'EOF'
feat(tables): routes POST additions/release, PATCH items

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8 : `SalesService.create` — ne libérer la table que si aucune autre addition n'est ouverte

**Files:**
- Modify: `apps/api/nestjs/src/pos/sales.service.ts:140-145`
- Test: `apps/api/nestjs/src/pos/sales.service.spec.ts:189-205`

- [ ] **Step 1 : Écrire le test qui échoue**

Dans `sales.service.spec.ts`, ajouter juste après le test `'closes the order and frees its table when the sale checks out a table addition'` (après la ligne 205) :

```typescript
  it('closes the order but keeps the table occupied when another addition is still open on it', async () => {
    (prisma.product as any).findMany.mockResolvedValue([product()]);
    (prisma.order as any).findFirst.mockResolvedValue({ id: 'order-1', status: 'open', tableId: 't1' });
    (prisma.order as any).count.mockResolvedValue(1);
    (prisma.sale as any).create.mockResolvedValue({ id: 'sale-1', items: [], payments: [] });

    await service.create('est-1', 'user-1', {
      orderId: 'order-1',
      items: [{ productId: 'p1', quantity: 1 }],
      payments: [{ method: 'cash', amount: 1000 }],
    } as any);

    expect(prisma.order.update).toHaveBeenCalledWith({
      where: { id: 'order-1' },
      data: { status: 'closed', closedAt: expect.any(Date) },
    });
    expect(prisma.restaurantTable.update).not.toHaveBeenCalled();
  });
```

Ajouter `count: vi.fn()` à l'entrée `order` de `makePrismaMock()` (ligne 17) :

```typescript
    order: { findFirst: vi.fn(), update: vi.fn(), count: vi.fn() },
```

Dans le test existant `'closes the order and frees its table when the sale checks out a table addition'` (ligne 189), ajouter avant l'appel à `service.create` :

```typescript
    (prisma.order as any).count.mockResolvedValue(0);
```

- [ ] **Step 2 : Lancer les tests pour vérifier qu'ils échouent**

Run: `cd apps/api/nestjs && npx vitest run src/pos/sales.service.spec.ts`
Expected: FAIL — `prisma.order.count` n'est jamais appelé, la table est toujours libérée inconditionnellement.

- [ ] **Step 3 : Implémenter**

Dans `sales.service.ts`, remplacer les lignes 140-145 :

```typescript
      if (orderToClose) {
        await tx.order.update({ where: { id: orderToClose.id }, data: { status: 'closed', closedAt: new Date() } });
        if (orderToClose.tableId) {
          await tx.restaurantTable.update({ where: { id: orderToClose.tableId }, data: { status: 'free' } });
        }
      }
```

par :

```typescript
      if (orderToClose) {
        await tx.order.update({ where: { id: orderToClose.id }, data: { status: 'closed', closedAt: new Date() } });
        if (orderToClose.tableId) {
          // Ne libérer la table que si aucune autre addition n'y reste ouverte
          // (le multi-addition par table permet plusieurs encaissements
          // indépendants sur une même table — voir docs/api/tables.md).
          const remainingOpenOrders = await tx.order.count({
            where: { tableId: orderToClose.tableId, status: 'open' },
          });
          if (remainingOpenOrders === 0) {
            await tx.restaurantTable.update({ where: { id: orderToClose.tableId }, data: { status: 'free' } });
          }
        }
      }
```

- [ ] **Step 4 : Lancer les tests pour vérifier qu'ils passent**

Run: `cd apps/api/nestjs && npx vitest run src/pos/sales.service.spec.ts`
Expected: PASS.

- [ ] **Step 5 : Commit**

```bash
git add apps/api/nestjs/src/pos/sales.service.ts apps/api/nestjs/src/pos/sales.service.spec.ts
git commit -m "$(cat <<'EOF'
fix(pos): ne libérer une table qu'en l'absence d'autre addition ouverte

Bug latent : le paiement d'une addition libérait systématiquement sa
table, même si une seconde addition restait ouverte dessus (multi-addition
par table).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9 : `TablesService.list` — agréger plusieurs additions ouvertes par table

**Files:**
- Modify: `apps/api/nestjs/src/tables/tables.service.ts:10-44`
- Test: `apps/api/nestjs/src/tables/tables.service.spec.ts:27-66`

- [ ] **Step 1 : Écrire les tests qui échouent**

Dans `tables.service.spec.ts`, remplacer le test `'lists tables scoped by establishment, ordered by zone then name'` (lignes 27-38) par :

```typescript
  it('lists tables scoped by establishment, ordered by zone then name', async () => {
    prisma.restaurantTable.findMany.mockResolvedValue([]);
    await service.list('est-1');
    expect(prisma.restaurantTable.findMany).toHaveBeenCalledWith({
      where: { establishmentId: 'est-1' },
      orderBy: [{ zone: 'asc' }, { name: 'asc' }],
      include: {
        orders: { where: { status: 'open' }, orderBy: { openedAt: 'asc' }, include: { items: true } },
        reservations: { where: { status: 'pending' }, orderBy: { reservedAt: 'asc' }, take: 1 },
      },
    });
  });
```

Remplacer le test `'derives guestCount and currentTotal from the open order, null when none'` (lignes 40-66) par :

```typescript
  it('derives guestCount and currentTotal from the open order, null when none', async () => {
    prisma.restaurantTable.findMany.mockResolvedValue([
      {
        id: 't1',
        establishmentId: 'est-1',
        name: 'T1',
        zone: null,
        status: 'occupied',
        createdAt: new Date('2026-01-01'),
        orders: [{ guestCount: 4, items: [{ quantity: 2, unitPrice: 700 }, { quantity: 1, unitPrice: 600 }] }],
        reservations: [],
      },
      {
        id: 't2',
        establishmentId: 'est-1',
        name: 'T2',
        zone: null,
        status: 'free',
        createdAt: new Date('2026-01-01'),
        orders: [],
        reservations: [],
      },
    ]);
    const result = await service.list('est-1');
    expect(result[0]).toMatchObject({ guestCount: 4, currentTotal: 2000, openOrderCount: 1, reservation: null });
    expect(result[1]).toMatchObject({ guestCount: null, currentTotal: null, openOrderCount: 0, reservation: null });
  });

  it('aggregates currentTotal across several open additions, using the guestCount of the oldest one', async () => {
    prisma.restaurantTable.findMany.mockResolvedValue([
      {
        id: 't1',
        establishmentId: 'est-1',
        name: 'T1',
        zone: null,
        status: 'occupied',
        createdAt: new Date('2026-01-01'),
        orders: [
          { guestCount: 2, items: [{ quantity: 1, unitPrice: 1000 }] },
          { guestCount: 3, items: [{ quantity: 1, unitPrice: 500 }] },
        ],
        reservations: [],
      },
    ]);
    const result = await service.list('est-1');
    expect(result[0]).toMatchObject({ guestCount: 2, currentTotal: 1500, openOrderCount: 2 });
  });
```

- [ ] **Step 2 : Lancer les tests pour vérifier qu'ils échouent**

Run: `cd apps/api/nestjs && npx vitest run src/tables/tables.service.spec.ts`
Expected: FAIL — `orders` est encore chargé avec `take: 1`, et `openOrderCount` n'existe pas dans la réponse.

- [ ] **Step 3 : Implémenter**

Remplacer la méthode `list` (lignes 10-44 de `tables.service.ts`) par :

```typescript
  async list(establishmentId: string) {
    const tables = await this.prisma.restaurantTable.findMany({
      where: { establishmentId },
      orderBy: [{ zone: 'asc' }, { name: 'asc' }],
      include: {
        // Toutes les additions ouvertes (pas juste la première — une table
        // peut en avoir plusieurs simultanément, voir docs/api/tables.md).
        orders: { where: { status: 'open' }, orderBy: { openedAt: 'asc' }, include: { items: true } },
        reservations: { where: { status: 'pending' }, orderBy: { reservedAt: 'asc' }, take: 1 },
      },
    });
    return tables.map((table) => {
      const orders = table.orders;
      const currentTotal =
        orders.length > 0
          ? orders.reduce(
              (sum, order) => sum + order.items.reduce((s, item) => s + Number(item.quantity) * Number(item.unitPrice), 0),
              0,
            )
          : null;
      // Le nombre de convives n'a pas vocation à se sommer entre plusieurs
      // additions — celui de la première addition ouverte (la plus ancienne).
      const guestCount = orders[0]?.guestCount ?? null;
      const reservation = table.reservations[0];
      return {
        id: table.id,
        establishmentId: table.establishmentId,
        name: table.name,
        zone: table.zone,
        status: table.status,
        createdAt: table.createdAt,
        guestCount,
        currentTotal,
        openOrderCount: orders.length,
        reservation: reservation
          ? {
              id: reservation.id,
              customerName: reservation.customerName,
              phone: reservation.phone,
              reservedAt: reservation.reservedAt,
            }
          : null,
      };
    });
  }
```

- [ ] **Step 4 : Lancer les tests pour vérifier qu'ils passent**

Run: `cd apps/api/nestjs && npx vitest run src/tables/tables.service.spec.ts`
Expected: PASS.

- [ ] **Step 5 : Commit**

```bash
git add apps/api/nestjs/src/tables/tables.service.ts apps/api/nestjs/src/tables/tables.service.spec.ts
git commit -m "$(cat <<'EOF'
fix(tables): TablesService.list agrège toutes les additions ouvertes

take: 1 ne récupérait qu'une seule addition — currentTotal/guestCount
étaient faux dès qu'une table avait plusieurs additions ouvertes. Nouveau
champ openOrderCount pour distinguer ce cas côté UI.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 10 : Vérification complète du backend et documentation

**Files:**
- Modify: `docs/api/tables.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1 : Lancer la suite complète, le lint et le build**

Run: `cd apps/api/nestjs && npm test && npm run lint && npm run build`
Expected: tous les tests passent, aucune erreur de lint (les deux warnings pré-existants `new Array(singleArgument)` dans `charts.service.ts` peuvent rester), build réussi.

- [ ] **Step 2 : Mettre à jour `docs/api/tables.md`**

Remplacer le bloc de routes (lignes 7-20) par :

```
GET    /establishments/:establishmentId/tables
POST   /establishments/:establishmentId/tables                       { name, zone? }
PATCH  /establishments/:establishmentId/tables/:tableId
DELETE /establishments/:establishmentId/tables/:tableId

POST   /establishments/:establishmentId/tables/:tableId/open
POST   /establishments/:establishmentId/tables/:tableId/additions    { guestCount? }
GET    /establishments/:establishmentId/tables/:tableId/orders
POST   /establishments/:establishmentId/tables/:tableId/release
POST   /establishments/:establishmentId/orders/:orderId/items        { productId, quantity, unitPrice? }
PATCH  /establishments/:establishmentId/orders/:orderId/items/:itemId { quantity }
DELETE /establishments/:establishmentId/orders/:orderId/items/:itemId
POST   /establishments/:establishmentId/orders/:orderId/transfer     { toTableId }
POST   /establishments/:establishmentId/orders/:orderId/merge        { intoOrderId }
POST   /establishments/:establishmentId/orders/:orderId/split        { itemIds, toTableId }
```

Remplacer le premier tiret de la section « Règles d'état » (ligne 26) par :

```
- **Plusieurs additions ouvertes par table sont supportées** : `openTable()` en crée la première (exige la table `free`/`reserved`) ; `openAdditionalOrder()` en ouvre une supplémentaire sur une table déjà `occupied`, sans toucher son statut ; `split()` reste l'autre façon d'en obtenir une seconde (diviser une addition existante). `TablesService.list()` agrège toutes les additions ouvertes d'une table (`openOrderCount`, `currentTotal` = somme, `guestCount` = celui de la plus ancienne).
- `release()` libère une table sans condition : toutes ses additions ouvertes passent `cancelled` (aucune vente, aucun impact stock), la table repasse `free`. Idempotent, aucune confirmation ni vérification de contenu côté serveur (décision utilisateur 2026-09-10).
```

Remplacer la ligne sur le prix unitaire (ligne 28) par :

```
- Le prix unitaire d'un produit à prix fixe est toujours relu depuis `product.salePrice` — jamais transmis par le client. Un produit à prix variable (Poulets, Poissons, Plats africains) exige `unitPrice` dans le corps de la requête. Ajouter le même produit au même prix incrémente la ligne existante plutôt que d'en créer une nouvelle (`OrdersService.addItem`) ; `PATCH .../items/:itemId` modifie la quantité d'une ligne déjà présente.
```

Remplacer la dernière ligne de la section (ligne 31) par :

```
- La clôture (`SalesService.create` avec `orderId`) vérifie que l'addition est encore `open`, puis dans la même transaction que la vente : ferme l'addition, et ne libère la table que si plus aucune autre addition n'y est ouverte (`SalesService.create`, corrigé le 2026-09-10 pour le multi-addition).
```

Remplacer la section « UI Flutter » (lignes 33-37) par :

```
## UI Flutter

[lib/tables/floor_plan_page.dart](../../apps/web/flutter/lib/tables/floor_plan_page.dart) : tables groupées par zone, couleur selon statut. Un tap sur une table occupée ouvre un menu (Gérer les additions / Nouvelle addition / Libérer la table / Modifier la table) plutôt que d'aller directement à l'addition — cohérent avec les menus déjà utilisés pour une table libre/réservée, qui gagnent aussi une entrée « Modifier la table » (en plus de l'appui long existant, conservé). [lib/tables/table_order_page.dart](../../apps/web/flutter/lib/tables/table_order_page.dart) (remplace l'ancien `order_detail_page.dart`) : reprend la grille produits + panier de la Caisse (composants partagés `lib/pos/product_grid.dart`/`lib/pos/cart_panel.dart`), avec un onglet par addition ouverte quand il y en a plusieurs. Chaque ajout/retrait/changement de quantité continue d'appeler le serveur immédiatement (pas de panier local en attente) — voir `docs/superpowers/specs/2026-09-10-table-order-caisse-design.md` pour le raisonnement complet.

**Fusion et division ne sont pas encore exposées dans l'UI** — le backend les supporte et sont testées, mais l'interface (choisir une addition/une table cible parmi plusieurs) est reportée à une prochaine itération pour rester dans un temps raisonnable.
```

- [ ] **Step 3 : Ajouter une entrée CHANGELOG**

Ajouter en tête de `CHANGELOG.md`, juste après la ligne `## [Unreleased]` :

```markdown
### Ajouté (post-plan, 2026-09-10) — Multi-additions par table, libération sans condition, écran Caisse-table
- **Libération d'une table sans condition** (`POST /tables/:tableId/release`) : toutes ses additions ouvertes sont annulées (aucun impact vente/stock), la table redevient libre — sans confirmation, accessible depuis le nouveau menu d'une table occupée.
- **Plusieurs additions simultanées sur une même table** : nouveau bouton « Nouvelle addition » (`POST /tables/:tableId/additions`) en plus de la scission déjà existante ; `GET /tables/:tableId/orders` liste désormais toutes les additions ouvertes. Correction de deux bugs latents trouvés en chemin : le paiement d'une addition libérait systématiquement sa table même si une autre addition y restait ouverte, et `TablesService.list` n'agrégeait qu'une seule addition par table pour le total/nombre de convives affichés.
- **Écran d'addition refondu** (`table_order_page.dart`, remplace `order_detail_page.dart`) : reprend la grille produits + panier de la Caisse (composants extraits et partagés dans `lib/pos/`) au lieu de la liste plate/dialogue texte précédents, avec un onglet par addition. Les produits à prix variable (Poulets, Poissons, Plats africains) deviennent commandables depuis une table (saisie du prix, comme en Caisse) — jusqu'ici explicitement refusés.
- **Modifier/supprimer une table** rendu plus découvrable : nouvelle entrée « Modifier la table » dans le menu de chaque table (en plus de l'appui long déjà existant, conservé).
- Voir `docs/superpowers/specs/2026-09-10-table-order-caisse-design.md` pour le design complet.
```

- [ ] **Step 4 : Commit**

```bash
git add docs/api/tables.md CHANGELOG.md
git commit -m "$(cat <<'EOF'
docs(tables): documente le multi-addition, la libération forcée, l'écran Caisse-table

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 11 : Modèles Flutter — `openOrderCount` sur `RestaurantTable`

**Files:**
- Modify: `apps/web/flutter/lib/tables/tables_models.dart:23-63`

- [ ] **Step 1 : Ajouter le champ**

Remplacer la classe `RestaurantTable` (lignes 23-63) par :

```dart
class RestaurantTable {
  RestaurantTable({
    required this.id,
    required this.name,
    this.zone,
    required this.status,
    this.guestCount,
    this.currentTotal,
    this.openOrderCount = 0,
    this.reservation,
  });

  final String id;
  final String name;
  final String? zone;
  final String status;

  /// Nombre de convives de l'addition ouverte la plus ancienne, le cas
  /// échéant (saisi à l'ouverture de la table — voir `TablesRepository.openTable`).
  final int? guestCount;

  /// Somme des totaux de toutes les additions ouvertes, le cas échéant.
  final double? currentTotal;

  /// Nombre d'additions ouvertes sur cette table — si > 1, l'UI affiche
  /// "N additions" plutôt que le total agrégé (ambigu sinon).
  final int openOrderCount;

  /// Réservation active (statut 'pending'), le cas échéant.
  final ReservationInfo? reservation;

  factory RestaurantTable.fromJson(Map<String, dynamic> json) =>
      RestaurantTable(
        id: json['id'] as String,
        name: json['name'] as String,
        zone: json['zone'] as String?,
        status: json['status'] as String,
        guestCount: json['guestCount'] as int?,
        currentTotal: (json['currentTotal'] as num?)?.toDouble(),
        openOrderCount: json['openOrderCount'] as int? ?? 0,
        reservation: json['reservation'] != null
            ? ReservationInfo.fromJson(
                json['reservation'] as Map<String, dynamic>,
              )
            : null,
      );
}
```

- [ ] **Step 2 : Vérifier l'analyse statique**

Run: `cd apps/web/flutter && flutter analyze lib/tables/tables_models.dart`
Expected: `No issues found!`

- [ ] **Step 3 : Commit**

```bash
git add apps/web/flutter/lib/tables/tables_models.dart
git commit -m "$(cat <<'EOF'
feat(tables): RestaurantTable.openOrderCount

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 12 : `TablesRepository` — nouvelles méthodes, méthodes modifiées

**Files:**
- Modify: `apps/web/flutter/lib/tables/tables_repository.dart`

- [ ] **Step 1 : Remplacer le fichier**

Remplacer le contenu complet de `tables_repository.dart` par :

```dart
import '../api/api_client.dart';
import 'tables_models.dart';

/// Correspond à apps/api/nestjs/src/tables/{tables,orders}.controller.ts.
class TablesRepository {
  TablesRepository(this._api, this.establishmentId);

  final ApiClient _api;
  final String establishmentId;

  String get _base => '/establishments/$establishmentId';

  Future<List<RestaurantTable>> listTables() async {
    final json = await _api.get('$_base/tables') as List<dynamic>;
    return json
        .map((e) => RestaurantTable.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createTable(String name, {String? zone}) {
    return _api.post('$_base/tables', body: {'name': name, 'zone': ?zone});
  }

  Future<void> updateTable(String tableId, {String? name, String? zone}) {
    return _api.patch(
      '$_base/tables/$tableId',
      body: {'name': ?name, 'zone': ?zone},
    );
  }

  Future<void> deleteTable(String tableId) {
    return _api.delete('$_base/tables/$tableId');
  }

  Future<OrderDetail> openTable(String tableId, {int? guestCount}) async {
    await _api.post(
      '$_base/tables/$tableId/open',
      body: {'guestCount': ?guestCount},
    );
    final orders = await listOpenOrdersForTable(tableId);
    return orders.first;
  }

  /// Ouvre une addition supplémentaire sur une table déjà occupée (bouton
  /// « Nouvelle addition ») — ne touche pas au statut de la table.
  Future<OrderDetail> openAdditionalOrder(String tableId, {int? guestCount}) async {
    final json = await _api.post(
      '$_base/tables/$tableId/additions',
      body: {'guestCount': ?guestCount},
    ) as Map<String, dynamic>;
    return OrderDetail.fromJson(json);
  }

  /// Libère la table sans condition : annule toutes ses additions ouvertes,
  /// aucune confirmation. Voir docs/api/tables.md.
  Future<void> releaseTable(String tableId) {
    return _api.post('$_base/tables/$tableId/release');
  }

  Future<void> createReservation(
    String tableId, {
    String? customerName,
    String? phone,
    required DateTime reservedAt,
  }) {
    return _api.post(
      '$_base/tables/$tableId/reservations',
      body: {
        'customerName': ?customerName,
        'phone': ?phone,
        'reservedAt': reservedAt.toUtc().toIso8601String(),
      },
    );
  }

  Future<void> cancelReservation(String reservationId) {
    return _api.post('$_base/reservations/$reservationId/cancel');
  }

  /// Toutes les additions ouvertes de la table (une table peut en avoir
  /// plusieurs simultanément — voir docs/api/tables.md).
  Future<List<OrderDetail>> listOpenOrdersForTable(String tableId) async {
    final json =
        await _api.get('$_base/tables/$tableId/orders') as List<dynamic>;
    return json
        .map((e) => OrderDetail.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addItem(
    String orderId, {
    required String productId,
    required double quantity,
    double? unitPrice,
  }) {
    return _api.post(
      '$_base/orders/$orderId/items',
      body: {
        'productId': productId,
        'quantity': quantity,
        'unitPrice': ?unitPrice,
      },
    );
  }

  Future<void> updateItemQuantity(String orderId, String itemId, double quantity) {
    return _api.patch(
      '$_base/orders/$orderId/items/$itemId',
      body: {'quantity': quantity},
    );
  }

  Future<void> removeItem(String orderId, String itemId) {
    return _api.delete('$_base/orders/$orderId/items/$itemId');
  }

  Future<void> transfer(String orderId, String toTableId) {
    return _api.post(
      '$_base/orders/$orderId/transfer',
      body: {'toTableId': toTableId},
    );
  }
}
```

- [ ] **Step 2 : Vérifier l'analyse statique**

Run: `cd apps/web/flutter && flutter analyze lib/tables/tables_repository.dart`
Expected: `No issues found!` (des erreurs sont attendues dans les fichiers qui appellent encore l'ancienne API — `floor_plan_page.dart`/`order_detail_page.dart` — corrigés dans les tâches suivantes ; ne pas s'en inquiéter à ce stade, seul ce fichier est vérifié ici).

- [ ] **Step 3 : Commit**

```bash
git add apps/web/flutter/lib/tables/tables_repository.dart
git commit -m "$(cat <<'EOF'
feat(tables): TablesRepository — additions, libération, quantité, prix variable

listOpenOrdersForTable remplace getOpenOrderForTable ; nouvelles méthodes
openAdditionalOrder/releaseTable/updateItemQuantity ; addItem accepte un
unitPrice optionnel.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 13 : Extraire la grille produits en composant partagé

**Files:**
- Create: `apps/web/flutter/lib/pos/product_grid.dart`
- Modify: `apps/web/flutter/lib/pos/pos_page.dart`

- [ ] **Step 1 : Créer le nouveau fichier**

```dart
import 'package:flutter/material.dart';

import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../common/formatting.dart';
import '../theme/app_theme.dart';

/// Grille de produits (recherche + filtre catégorie + grille avec photos) —
/// extraite de `PosPage` pour être réutilisée telle quelle par l'écran de
/// table (`table_order_page.dart`). Ne connaît rien du panier appelant, juste
/// `quantityInCart`/`onProductTap`.
class ProductGrid extends StatelessWidget {
  const ProductGrid({
    super.key,
    required this.repository,
    required this.categories,
    required this.products,
    required this.search,
    required this.categoryId,
    required this.quantityInCart,
    required this.onSearchChanged,
    required this.onCategoryChanged,
    required this.onProductTap,
    required this.crossAxisExtent,
  });

  final CatalogRepository repository;
  final List<Category> categories;
  final List<Product> products;
  final String search;
  final String? categoryId;
  final int Function(String productId) quantityInCart;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<Product> onProductTap;
  final double crossAxisExtent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Rechercher un produit',
              isDense: true,
            ),
            onChanged: onSearchChanged,
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: const Text('Tous'),
                  selected: categoryId == null,
                  onSelected: (_) => onCategoryChanged(null),
                ),
              ),
              for (final category in categories)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(category.name),
                    selected: categoryId == category.id,
                    onSelected: (_) => onCategoryChanged(category.id),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: crossAxisExtent,
              mainAxisExtent: 132,
            ),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return PosProductTile(
                product: product,
                repository: repository,
                quantityInCart: quantityInCart(product.id),
                onTap: () => onProductTap(product),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Barre flottante « N articles · total FCFA » affichée en mobile quand le
/// panier n'est pas vide — tap ouvre le panneau panier en feuille modale.
class FloatingCartBar extends StatelessWidget {
  const FloatingCartBar({
    super.key,
    required this.itemCount,
    required this.total,
    required this.onTap,
  });

  final int itemCount;
  final double total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Material(
          color: AppColors.green,
          borderRadius: BorderRadius.circular(14),
          elevation: 3,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Icon(
                    Icons.shopping_cart,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$itemCount article${itemCount > 1 ? 's' : ''} · ${formatAmount(total)} FCFA',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Voir le panier',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PosProductTile extends StatelessWidget {
  const PosProductTile({
    super.key,
    required this.product,
    required this.repository,
    required this.quantityInCart,
    required this.onTap,
  });

  final Product product;
  final CatalogRepository repository;
  final int quantityInCart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primaryImage =
        product.images.where((i) => i.isPrimary).firstOrNull ??
        product.images.firstOrNull;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: primaryImage == null
                      ? const ColoredBox(
                          color: AppColors.greenLight,
                          child: Icon(
                            Icons.local_drink_outlined,
                            size: 26,
                            color: AppColors.green,
                          ),
                        )
                      : FutureBuilder<String>(
                          future: repository.getImageUrl(
                            product.id,
                            primaryImage.id,
                            variant: 'thumbnail',
                          ),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const ColoredBox(
                                color: AppColors.greenLight,
                              );
                            }
                            return ColoredBox(
                              color: AppColors.greenLight,
                              child: Image.network(
                                snapshot.data!,
                                fit: BoxFit.contain,
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13),
                      ),
                      Text(
                        product.salePrice != null
                            ? '${formatAmount(product.salePrice!)} FCFA'
                            : 'Prix variable',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (quantityInCart > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.orange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$quantityInCart',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2 : Vérifier l'analyse statique du nouveau fichier**

Run: `cd apps/web/flutter && flutter analyze lib/pos/product_grid.dart`
Expected: `No issues found!`

- [ ] **Step 3 : Commit**

```bash
git add apps/web/flutter/lib/pos/product_grid.dart
git commit -m "$(cat <<'EOF'
refactor(pos): extrait ProductGrid/PosProductTile/FloatingCartBar en composants partagés

Code identique à celui de pos_page.dart, déplacé tel quel — pos_page.dart
sera mis à jour pour les consommer dans une tâche suivante. Permet la
réutilisation par le futur écran de table (table_order_page.dart).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 14 : Extraire le panier en composant partagé générique

**Files:**
- Create: `apps/web/flutter/lib/pos/cart_panel.dart`

- [ ] **Step 1 : Créer le nouveau fichier**

```dart
import 'package:flutter/material.dart';

import '../common/formatting.dart';
import '../theme/app_theme.dart';

/// Panneau panier — partagé entre `PosPage` (panier local, `T = CartLine`) et
/// l'écran de table (`T = OrderItemDetail`, panier persisté serveur). Générique
/// sur le type de ligne pour ne pas imposer de forme de données commune :
/// chaque appelant fournit juste comment en extraire nom/quantité/prix, et
/// récupère l'objet d'origine dans `onChangeQuantity` pour agir dessus à sa
/// façon (mutation locale pour la Caisse, appel serveur pour la table).
class CartPanel<T> extends StatelessWidget {
  const CartPanel({
    super.key,
    required this.lines,
    required this.nameOf,
    required this.quantityOf,
    required this.unitPriceOf,
    required this.subtotal,
    required this.isCharging,
    required this.onChangeQuantity,
    required this.onCheckout,
    this.scrollController,
  });

  final List<T> lines;
  final String Function(T line) nameOf;
  final double Function(T line) quantityOf;
  final double Function(T line) unitPriceOf;
  final double subtotal;
  final bool isCharging;
  final void Function(T line, int delta) onChangeQuantity;
  final VoidCallback onCheckout;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (scrollController != null)
          const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 4),
            child: SizedBox(width: 36, child: Divider(thickness: 4, height: 4)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              const Text(
                'Panier',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const Spacer(),
              if (scrollController != null)
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
            ],
          ),
        ),
        Expanded(
          child: lines.isEmpty
              ? const Center(child: Text('Panier vide'))
              : ListView(
                  controller: scrollController,
                  children: [
                    for (final line in lines)
                      ListTile(
                        title: Text(nameOf(line)),
                        subtitle: Text(
                          '${formatAmount(unitPriceOf(line))} FCFA x ${quantityOf(line).toStringAsFixed(0)}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: AppColors.alert,
                              ),
                              onPressed: () => onChangeQuantity(line, -1),
                            ),
                            Text(quantityOf(line).toStringAsFixed(0)),
                            IconButton(
                              icon: const Icon(
                                Icons.add_circle_outline,
                                color: AppColors.green,
                              ),
                              onPressed: () => onChangeQuantity(line, 1),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  const Text(
                    'Total',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const Spacer(),
                  Text(
                    '${formatAmount(subtotal)} FCFA',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: lines.isEmpty || isCharging ? null : onCheckout,
                child: isCharging
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Encaisser'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2 : Vérifier l'analyse statique**

Run: `cd apps/web/flutter && flutter analyze lib/pos/cart_panel.dart`
Expected: `No issues found!`

- [ ] **Step 3 : Commit**

```bash
git add apps/web/flutter/lib/pos/cart_panel.dart
git commit -m "$(cat <<'EOF'
refactor(pos): extrait CartPanel<T>, générique sur le type de ligne de panier

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 15 : Brancher `pos_page.dart` sur les composants partagés

**Files:**
- Modify: `apps/web/flutter/lib/pos/pos_page.dart`

- [ ] **Step 1 : Remplacer le fichier**

Remplacer le contenu complet de `pos_page.dart` par :

```dart
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../catalog/catalog_cache.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../sync/device_id.dart';
import '../sync/pending_operation.dart';
import '../sync/sync_queue_service.dart';
import '../sync/sync_status_bar.dart';
import 'cart_panel.dart';
import 'payment_dialog.dart';
import 'pos_models.dart';
import 'pos_repository.dart';
import 'product_grid.dart';
import 'receipt_page.dart';

/// Largeur en dessous de laquelle le panier passe en panneau inférieur
/// (bottom sheet + barre flottante) plutôt qu'en colonne latérale fixe —
/// recommandation de "Nouvel interface _ 1.docx" : le panier ne doit jamais
/// se retrouver compressé sur un écran de smartphone.
const _kMobileBreakpoint = 700.0;

class PosPage extends StatefulWidget {
  const PosPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  late final CatalogRepository _catalog = CatalogRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final PosRepository _pos = PosRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final CatalogCache _cache = CatalogCache(widget.establishmentId);
  late final SyncQueueService _syncQueue = SyncQueueService(
    ApiClient(),
    widget.establishmentId,
  );
  late Future<(List<Category>, List<Product>)> _future = _load();

  final List<CartLine> _cart = [];
  String _search = '';
  String? _categoryId;
  bool _isCharging = false;

  Future<(List<Category>, List<Product>)> _load() async {
    try {
      final categories = await _catalog.listCategories();
      final products = await _catalog.listProducts();
      await _cache.save(categories, products);
      return (categories, products);
    } catch (error) {
      final cached = await _cache.load();
      if (cached != null) return cached; // offline: fall back to the last known catalog (prompt maître §25).
      rethrow;
    }
  }

  double get _subtotal => _cart.fold(0, (sum, line) => sum + line.lineTotal);
  int get _itemCount => _cart.fold(0, (sum, line) => sum + line.quantity);

  Future<void> _addToCart(Product product) async {
    // Catégorie à prix variable (ex. Poulets/Poissons/Plats africains) :
    // aucun prix par défaut à proposer — le caissier le saisit à chaque
    // ajout, une ligne distincte par prix saisi (deux pièces de poulet
    // peuvent valoir des prix différents le même jour).
    if (product.salePrice == null) {
      final price = await _promptManualPrice(product);
      if (price == null) return;
      setState(
        () => _cart.add(
          CartLine(product: product, quantity: 1, manualUnitPrice: price),
        ),
      );
      return;
    }
    setState(() {
      final existing = _cart
          .where((l) => l.product.id == product.id)
          .firstOrNull;
      if (existing != null) {
        existing.quantity++;
      } else {
        _cart.add(CartLine(product: product, quantity: 1));
      }
    });
  }

  Future<double?> _promptManualPrice(Product product) async {
    final controller = TextEditingController();
    return showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Prix de vente — ${product.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Prix (FCFA)'),
          onSubmitted: (_) {
            final value = double.tryParse(
              controller.text.trim().replaceAll(',', '.'),
            );
            if (value != null && value > 0) Navigator.of(context).pop(value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(
                controller.text.trim().replaceAll(',', '.'),
              );
              if (value == null || value <= 0) return;
              Navigator.of(context).pop(value);
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  void _changeQuantity(CartLine line, int delta) {
    setState(() {
      line.quantity += delta;
      if (line.quantity <= 0) _cart.remove(line);
    });
  }

  int _quantityInCart(String productId) => _cart
      .where((l) => l.product.id == productId)
      .fold(0, (sum, l) => sum + l.quantity);

  Future<void> _checkout() async {
    if (_cart.isEmpty) return;
    final total = _subtotal;
    // Bières/Vins/Sucreries -> N° de la commande ; Poulets/Poissons/Plats
    // africains -> N° de marché (voir docs/api/pos.md) — un seul champ de
    // chaque affiché si le panier contient au moins un produit du groupe
    // concerné, jamais par ligne.
    final hasCasePricingItems = _cart.any((l) => l.product.hasCasePricing);
    final hasVariablePricingItems = _cart.any((l) => l.product.hasVariablePricing);
    final outcome = await showPaymentDialog(
      context,
      total: total,
      showOrderNumberField: hasCasePricingItems,
      showMarketNumberField: hasVariablePricingItems,
      fetchLastOrderNumber: hasCasePricingItems ? _pos.lastOrderNumber : null,
      fetchLastMarketNumber: hasVariablePricingItems ? _pos.lastMarketNumber : null,
    );
    if (outcome == null) return;

    final saleId = const Uuid().v4();
    final items = _cart
        .map(
          (l) => {
            'productId': l.product.id,
            'quantity': l.quantity,
            if (l.manualUnitPrice != null) 'unitPrice': l.manualUnitPrice,
          },
        )
        .toList();
    final payments = outcome.lines
        .map((p) => {'method': p.method, 'amount': p.amount})
        .toList();

    setState(() => _isCharging = true);
    try {
      final sale = await _pos.createSale(
        id: saleId,
        items: items,
        payments: payments,
        orderNumber: outcome.orderNumber,
        marketNumber: outcome.marketNumber,
      );
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _future = _load();
      });
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => ReceiptPage(sale: sale)));
    } on ApiException catch (e) {
      // A real business rejection (bad request, insufficient stock, ...) —
      // replaying it later wouldn't help, so it is never queued offline.
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      // No HTTP response at all reached us — treat as offline and queue the
      // sale for later sync (prompt maître §25), using saleId as the
      // idempotency key so a retry can never double-charge stock.
      await _syncQueue.enqueue(
        PendingOperation(
          id: saleId,
          entityType: 'sale',
          deviceId: await getDeviceId(),
          payload: {
            'items': items,
            'payments': payments,
            'orderNumber': ?outcome.orderNumber,
            'marketNumber': ?outcome.marketNumber,
          },
          createdAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      setState(() => _cart.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hors ligne : vente enregistrée localement, elle sera synchronisée automatiquement.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isCharging = false);
    }
  }

  void _openCartSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => CartPanel<CartLine>(
          lines: _cart,
          nameOf: (l) => l.product.name,
          quantityOf: (l) => l.quantity.toDouble(),
          unitPriceOf: (l) => l.unitPrice,
          subtotal: _subtotal,
          isCharging: _isCharging,
          onChangeQuantity: (line, delta) => setState(() {
            _changeQuantity(line, delta);
            if (_cart.isEmpty) Navigator.of(sheetContext).maybePop();
          }),
          onCheckout: () async {
            Navigator.of(sheetContext).pop();
            await _checkout();
          },
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Caisse')),
      body: Column(
        children: [
          SyncStatusBar(syncQueue: _syncQueue),
          Expanded(
            child: FutureBuilder<(List<Category>, List<Product>)>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  final message = snapshot.error is ApiException
                      ? (snapshot.error as ApiException).message
                      : '${snapshot.error}';
                  return Center(child: Text(message));
                }

                final (categories, allProducts) = snapshot.data!;
                final products = allProducts.where((p) {
                  final matchesSearch =
                      _search.isEmpty ||
                      p.name.toLowerCase().contains(_search.toLowerCase());
                  final matchesCategory =
                      _categoryId == null || p.categoryId == _categoryId;
                  return matchesSearch &&
                      matchesCategory &&
                      p.status == 'active';
                }).toList();

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < _kMobileBreakpoint;
                    final grid = ProductGrid(
                      repository: _catalog,
                      categories: categories,
                      products: products,
                      search: _search,
                      categoryId: _categoryId,
                      quantityInCart: _quantityInCart,
                      onSearchChanged: (value) =>
                          setState(() => _search = value),
                      onCategoryChanged: (value) =>
                          setState(() => _categoryId = value),
                      onProductTap: _addToCart,
                      crossAxisExtent: isMobile ? 130 : 160,
                    );

                    if (!isMobile) {
                      return Row(
                        children: [
                          Expanded(flex: 3, child: grid),
                          const VerticalDivider(width: 1),
                          Expanded(
                            flex: 2,
                            child: CartPanel<CartLine>(
                              lines: _cart,
                              nameOf: (l) => l.product.name,
                              quantityOf: (l) => l.quantity.toDouble(),
                              unitPriceOf: (l) => l.unitPrice,
                              subtotal: _subtotal,
                              isCharging: _isCharging,
                              onChangeQuantity: (line, delta) =>
                                  _changeQuantity(line, delta),
                              onCheckout: _checkout,
                            ),
                          ),
                        ],
                      );
                    }

                    return Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 64),
                          child: grid,
                        ),
                        if (_cart.isNotEmpty)
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: FloatingCartBar(
                              itemCount: _itemCount,
                              total: _subtotal,
                              onTap: _openCartSheet,
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2 : Lancer l'analyse et les tests**

Run: `cd apps/web/flutter && flutter analyze lib/pos/ && flutter test`
Expected: `No issues found!`, tous les tests existants passent toujours (aucun test dédié à `pos_page.dart` à ce jour, mais `widget_test.dart`/les autres ne doivent pas régresser).

- [ ] **Step 3 : Lancer le build**

Run: `cd apps/web/flutter && flutter build web --release`
Expected: `√ Built build\web`

- [ ] **Step 4 : Commit**

```bash
git add apps/web/flutter/lib/pos/pos_page.dart
git commit -m "$(cat <<'EOF'
refactor(pos): PosPage consomme ProductGrid/CartPanel partagés

Aucun changement de comportement — pure extraction, vérifiée par
flutter analyze/test/build.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 16 : Nouvel écran `TableOrderPage`

**Files:**
- Create: `apps/web/flutter/lib/tables/table_order_page.dart`
- Delete: `apps/web/flutter/lib/tables/order_detail_page.dart`

- [ ] **Step 1 : Créer le nouvel écran**

```dart
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../pos/cart_panel.dart';
import '../pos/payment_dialog.dart';
import '../pos/pos_repository.dart';
import '../pos/product_grid.dart';
import '../pos/receipt_page.dart';
import '../theme/app_theme.dart';
import 'tables_models.dart';
import 'tables_repository.dart';

/// Écran d'une table occupée : une addition (ou plusieurs, en onglets) avec
/// la grille produits + panier de la Caisse (composants partagés de `lib/pos/`).
/// Contrairement à `PosPage`, chaque ajout/retrait/changement de quantité
/// appelle le serveur immédiatement (persistance immédiate, addition visible
/// en temps réel par un autre appareil) — voir
/// docs/superpowers/specs/2026-09-10-table-order-caisse-design.md.
class TableOrderPage extends StatefulWidget {
  const TableOrderPage({
    super.key,
    required this.repository,
    required this.establishmentId,
    required this.tableId,
  });

  final TablesRepository repository;
  final String establishmentId;
  final String tableId;

  @override
  State<TableOrderPage> createState() => _TableOrderPageState();
}

class _TableOrderPageState extends State<TableOrderPage> {
  late final CatalogRepository _catalog = CatalogRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final PosRepository _pos = PosRepository(
    ApiClient(),
    widget.establishmentId,
  );

  Future<List<OrderDetail>>? _ordersFuture;
  Future<(List<Category>, List<Product>)>? _catalogFuture;
  int _selectedIndex = 0;
  String _search = '';
  String? _categoryId;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _catalogFuture = _loadCatalog();
    _reloadOrders();
  }

  Future<(List<Category>, List<Product>)> _loadCatalog() async {
    final categories = await _catalog.listCategories();
    final products = await _catalog.listProducts();
    return (categories, products);
  }

  void _reloadOrders() {
    final future = widget.repository.listOpenOrdersForTable(widget.tableId);
    future.ignore();
    setState(() {
      _ordersFuture = future;
      _selectedIndex = 0;
    });
  }

  Future<void> _addNewAddition() async {
    setState(() => _isBusy = true);
    try {
      await widget.repository.openAdditionalOrder(widget.tableId);
      final orders = await widget.repository.listOpenOrdersForTable(widget.tableId);
      if (!mounted) return;
      setState(() {
        _ordersFuture = Future.value(orders);
        _selectedIndex = orders.length - 1;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<double?> _promptManualPrice(Product product) async {
    final controller = TextEditingController();
    return showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Prix de vente — ${product.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Prix (FCFA)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(
                controller.text.trim().replaceAll(',', '.'),
              );
              if (value == null || value <= 0) return;
              Navigator.of(context).pop(value);
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  Future<void> _addProduct(OrderDetail order, Product product) async {
    double? unitPrice;
    if (product.salePrice == null) {
      unitPrice = await _promptManualPrice(product);
      if (unitPrice == null) return;
    }
    setState(() => _isBusy = true);
    try {
      await widget.repository.addItem(
        order.id,
        productId: product.id,
        quantity: 1,
        unitPrice: unitPrice,
      );
      _reloadOrders();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _changeQuantity(OrderDetail order, OrderItemDetail item, int delta) async {
    final nextQuantity = item.quantity + delta;
    setState(() => _isBusy = true);
    try {
      if (nextQuantity <= 0) {
        await widget.repository.removeItem(order.id, item.id);
      } else {
        await widget.repository.updateItemQuantity(order.id, item.id, nextQuantity);
      }
      _reloadOrders();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _checkout(OrderDetail order) async {
    if (order.items.isEmpty) return;
    final hasCasePricingItems = order.items.any((i) => i.hasCasePricing);
    final hasVariablePricingItems = order.items.any((i) => i.hasVariablePricing);
    final outcome = await showPaymentDialog(
      context,
      total: order.total,
      showOrderNumberField: hasCasePricingItems,
      showMarketNumberField: hasVariablePricingItems,
      fetchLastOrderNumber: hasCasePricingItems ? _pos.lastOrderNumber : null,
      fetchLastMarketNumber: hasVariablePricingItems ? _pos.lastMarketNumber : null,
    );
    if (outcome == null) return;

    setState(() => _isBusy = true);
    try {
      final sale = await _pos.createSale(
        items: order.items
            .map((i) => {'productId': i.productId, 'quantity': i.quantity})
            .toList(),
        payments: outcome.lines
            .map((p) => {'method': p.method, 'amount': p.amount})
            .toList(),
        orderId: order.id,
        tableId: widget.tableId,
        source: 'table',
        orderNumber: outcome.orderNumber,
        marketNumber: outcome.marketNumber,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ReceiptPage(sale: sale)),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Addition'),
        actions: [
          IconButton(
            tooltip: 'Nouvelle addition',
            icon: const Icon(Icons.add_box_outlined),
            onPressed: _isBusy ? null : _addNewAddition,
          ),
        ],
      ),
      body: FutureBuilder<List<OrderDetail>>(
        future: _ordersFuture,
        builder: (context, ordersSnapshot) {
          if (ordersSnapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (ordersSnapshot.hasError) {
            final message = ordersSnapshot.error is ApiException
                ? (ordersSnapshot.error as ApiException).message
                : '${ordersSnapshot.error}';
            return Center(child: Text(message));
          }
          final orders = ordersSnapshot.data!;
          final selectedIndex = _selectedIndex.clamp(0, orders.length - 1);
          final order = orders[selectedIndex];

          return Column(
            children: [
              if (orders.length > 1)
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (var i = 0; i < orders.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text('Addition ${i + 1} (${orders[i].items.length})'),
                            selected: i == selectedIndex,
                            selectedColor: AppColors.green,
                            onSelected: (_) => setState(() => _selectedIndex = i),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: FutureBuilder<(List<Category>, List<Product>)>(
                  future: _catalogFuture,
                  builder: (context, catalogSnapshot) {
                    if (catalogSnapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (catalogSnapshot.hasError) {
                      final message = catalogSnapshot.error is ApiException
                          ? (catalogSnapshot.error as ApiException).message
                          : '${catalogSnapshot.error}';
                      return Center(child: Text(message));
                    }
                    final (categories, allProducts) = catalogSnapshot.data!;
                    final products = allProducts.where((p) {
                      final matchesSearch =
                          _search.isEmpty ||
                          p.name.toLowerCase().contains(_search.toLowerCase());
                      final matchesCategory =
                          _categoryId == null || p.categoryId == _categoryId;
                      return matchesSearch && matchesCategory && p.status == 'active';
                    }).toList();

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final isMobile = constraints.maxWidth < 700;
                        final grid = ProductGrid(
                          repository: _catalog,
                          categories: categories,
                          products: products,
                          search: _search,
                          categoryId: _categoryId,
                          quantityInCart: (productId) => order.items
                              .where((i) => i.productId == productId)
                              .fold(0, (sum, i) => sum + i.quantity.round()),
                          onSearchChanged: (value) => setState(() => _search = value),
                          onCategoryChanged: (value) => setState(() => _categoryId = value),
                          onProductTap: (product) => _addProduct(order, product),
                          crossAxisExtent: isMobile ? 130 : 160,
                        );
                        final cart = CartPanel<OrderItemDetail>(
                          lines: order.items,
                          nameOf: (i) => i.productName,
                          quantityOf: (i) => i.quantity,
                          unitPriceOf: (i) => i.unitPrice,
                          subtotal: order.total,
                          isCharging: _isBusy,
                          onChangeQuantity: (item, delta) => _changeQuantity(order, item, delta),
                          onCheckout: () => _checkout(order),
                        );

                        if (!isMobile) {
                          return Row(
                            children: [
                              Expanded(flex: 3, child: grid),
                              const VerticalDivider(width: 1),
                              Expanded(flex: 2, child: cart),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            Expanded(child: grid),
                            SizedBox(height: 280, child: cart),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 2 : Ajouter `hasCasePricing`/`hasVariablePricing` sur `OrderItemDetail`**

`_checkout` ci-dessus utilise `i.hasCasePricing`/`i.hasVariablePricing`, qui n'existent pas encore sur `OrderItemDetail`. Dans `tables_models.dart`, la classe `OrderItemDetail` ne porte pas la catégorie du produit — l'ajouter nécessiterait d'étendre la réponse serveur. Plus simple et suffisant : dans `orders.service.ts` (`listOpenOrdersForTable`, Task 5), le `select` du produit inclut déjà `name` ; l'étendre pour inclure aussi la catégorie.

Dans `apps/api/nestjs/src/tables/orders.service.ts`, modifier `listOpenOrdersForTable` (ajoutée à la Task 5) :

```typescript
  async listOpenOrdersForTable(establishmentId: string, tableId: string) {
    const orders = await this.prisma.order.findMany({
      where: { establishmentId, tableId, status: 'open' },
      orderBy: { openedAt: 'asc' },
      include: {
        items: {
          include: { product: { select: { name: true, category: { select: { hasCasePricing: true, hasVariablePricing: true } } } } },
        },
      },
    });
    if (orders.length === 0) {
      throw new NotFoundException('Aucune addition ouverte pour cette table');
    }
    return orders;
  }
```

Dans `apps/api/nestjs/src/tables/orders.service.spec.ts`, adapter l'assertion du test `'returns every open order for the table, each with its items'` (Task 5) :

```typescript
    expect(prisma.order.findMany).toHaveBeenCalledWith({
      where: { establishmentId: 'est-1', tableId: 't1', status: 'open' },
      orderBy: { openedAt: 'asc' },
      include: {
        items: {
          include: { product: { select: { name: true, category: { select: { hasCasePricing: true, hasVariablePricing: true } } } } },
        },
      },
    });
```

Dans `apps/web/flutter/lib/tables/tables_models.dart`, étendre `OrderItemDetail` :

```dart
class OrderItemDetail {
  OrderItemDetail({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.hasCasePricing = false,
    this.hasVariablePricing = false,
  });

  final String id;
  final String productId;
  final String productName;
  final double quantity;
  final double unitPrice;
  final bool hasCasePricing;
  final bool hasVariablePricing;

  factory OrderItemDetail.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>?;
    final category = product?['category'] as Map<String, dynamic>?;
    return OrderItemDetail(
      id: json['id'] as String,
      productId: json['productId'] as String,
      productName: product?['name'] as String? ?? '',
      quantity: (json['quantity'] as num).toDouble(),
      unitPrice: (json['unitPrice'] as num).toDouble(),
      hasCasePricing: category?['hasCasePricing'] as bool? ?? false,
      hasVariablePricing: category?['hasVariablePricing'] as bool? ?? false,
    );
  }
}
```

- [ ] **Step 3 : Supprimer l'ancien écran**

```bash
git rm apps/web/flutter/lib/tables/order_detail_page.dart
```

- [ ] **Step 4 : Vérifier l'analyse statique**

Run: `cd apps/web/flutter && flutter analyze lib/tables/`
Expected: des erreurs sont encore attendues dans `floor_plan_page.dart` (référence encore `OrderDetailPage`, corrigé dans la tâche suivante) — vérifier que `table_order_page.dart` lui-même ne produit aucune erreur propre.

- [ ] **Step 5 : Commit**

```bash
git add apps/web/flutter/lib/tables/table_order_page.dart apps/web/flutter/lib/tables/tables_models.dart apps/api/nestjs/src/tables/orders.service.ts apps/api/nestjs/src/tables/orders.service.spec.ts
git commit -m "$(cat <<'EOF'
feat(tables): nouvel écran TableOrderPage (remplace OrderDetailPage)

Onglets par addition ouverte, grille + panier Caisse partagés, prix
variable supporté. OrderItemDetail porte désormais hasCasePricing/
hasVariablePricing (nécessaire au choix des champs N° commande/marché à
l'encaissement, comme en Caisse).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 17 : Refonte des menus de `floor_plan_page.dart`

**Files:**
- Modify: `apps/web/flutter/lib/tables/floor_plan_page.dart`

- [ ] **Step 1 : Remplacer le fichier**

Remplacer le contenu complet de `floor_plan_page.dart` par :

```dart
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../common/formatting.dart';
import '../theme/app_theme.dart';
import 'table_order_page.dart';
import 'tables_models.dart';
import 'tables_repository.dart';

class FloorPlanPage extends StatefulWidget {
  const FloorPlanPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<FloorPlanPage> createState() => _FloorPlanPageState();
}

const _kAllFilter = 'all';

class _FloorPlanPageState extends State<FloorPlanPage> {
  late final TablesRepository _repository = TablesRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late Future<List<RestaurantTable>> _future = _repository.listTables();
  String _filter = _kAllFilter;
  String _search = '';

  void _reload() => setState(() => _future = _repository.listTables());

  // Regroupe le statut brut (chaîne libre côté API) dans l'un des filtres
  // affichés — même logique que _statusLabel, seulement pour le filtrage.
  String _statusBucket(String status) {
    switch (status) {
      case 'free':
        return 'free';
      case 'billing':
        return 'billing';
      case 'reserved':
        return 'reserved';
      default:
        return 'occupied';
    }
  }

  Future<void> _onTableTap(RestaurantTable table) async {
    switch (table.status) {
      case 'free':
        await _showFreeTableActions(table);
        return;
      case 'reserved':
        await _showReservedTableActions(table);
        return;
      default:
        await _showOccupiedTableActions(table);
    }
  }

  Future<void> _goToOrder(RestaurantTable table) async {
    try {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TableOrderPage(
            repository: _repository,
            establishmentId: widget.establishmentId,
            tableId: table.id,
          ),
        ),
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openTableWithGuestCount(RestaurantTable table) async {
    final guestCount = await _promptGuestCount();
    try {
      await _repository.openTable(table.id, guestCount: guestCount);
      await _goToOrder(table);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<int?> _promptGuestCount() async {
    final controller = TextEditingController();
    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ouvrir la table'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Nombre de convives (facultatif)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Passer'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(int.tryParse(controller.text.trim())),
            child: const Text('Ouvrir'),
          ),
        ],
      ),
    );
  }

  Future<void> _showFreeTableActions(RestaurantTable table) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  table.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.event_seat_outlined,
                color: AppColors.green,
              ),
              title: const Text('Ouvrir la table'),
              onTap: () => Navigator.of(sheetContext).pop('open'),
            ),
            ListTile(
              leading: const Icon(
                Icons.event_available_outlined,
                color: AppColors.orange,
              ),
              title: const Text('Réserver'),
              onTap: () => Navigator.of(sheetContext).pop('reserve'),
            ),
            ListTile(
              leading: const Icon(
                Icons.edit_outlined,
                color: AppColors.textSecondary,
              ),
              title: const Text('Modifier la table'),
              onTap: () => Navigator.of(sheetContext).pop('edit'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'open') {
      await _openTableWithGuestCount(table);
    } else if (action == 'reserve') {
      await _showReserveDialog(table);
    } else if (action == 'edit') {
      await _showEditTableDialog(table);
    }
  }

  Future<void> _showReserveDialog(RestaurantTable table) async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    DateTime selected = DateTime.now().add(const Duration(hours: 1));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Réserver ${table.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Nom du client (facultatif)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Téléphone (facultatif)',
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule_outlined),
                label: Text(
                  '${selected.day}/${selected.month}/${selected.year} à ${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}',
                ),
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: selected,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date == null) return;
                  if (!context.mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(selected),
                  );
                  if (time == null) return;
                  setDialogState(
                    () => selected = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    ),
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Réserver'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _repository.createReservation(
        table.id,
        customerName: nameController.text.trim().isEmpty
            ? null
            : nameController.text.trim(),
        phone: phoneController.text.trim().isEmpty
            ? null
            : phoneController.text.trim(),
        reservedAt: selected,
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _showReservedTableActions(RestaurantTable table) async {
    final reservation = table.reservation;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    table.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (reservation != null) ...[
                    const SizedBox(height: 4),
                    if (reservation.customerName != null)
                      Text(reservation.customerName!),
                    if (reservation.phone != null)
                      Text(
                        reservation.phone!,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    Text(
                      'Réservée pour ${reservation.reservedAt.toLocal().hour.toString().padLeft(2, '0')}:${reservation.reservedAt.toLocal().minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(
                Icons.event_seat_outlined,
                color: AppColors.green,
              ),
              title: const Text('Client arrivé — ouvrir la table'),
              onTap: () => Navigator.of(sheetContext).pop('open'),
            ),
            ListTile(
              leading: const Icon(
                Icons.event_busy_outlined,
                color: AppColors.alert,
              ),
              title: const Text('Annuler la réservation'),
              onTap: () => Navigator.of(sheetContext).pop('cancel'),
            ),
            ListTile(
              leading: const Icon(
                Icons.edit_outlined,
                color: AppColors.textSecondary,
              ),
              title: const Text('Modifier la table'),
              onTap: () => Navigator.of(sheetContext).pop('edit'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'open') {
      await _openTableWithGuestCount(table);
    } else if (action == 'cancel' && reservation != null) {
      try {
        await _repository.cancelReservation(reservation.id);
        _reload();
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } else if (action == 'edit') {
      await _showEditTableDialog(table);
    }
  }

  Future<void> _showOccupiedTableActions(RestaurantTable table) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  table.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.receipt_long_outlined,
                color: AppColors.green,
              ),
              title: const Text('Gérer les additions'),
              onTap: () => Navigator.of(sheetContext).pop('manage'),
            ),
            ListTile(
              leading: const Icon(
                Icons.add_box_outlined,
                color: AppColors.orange,
              ),
              title: const Text('Nouvelle addition'),
              onTap: () => Navigator.of(sheetContext).pop('new_addition'),
            ),
            ListTile(
              leading: const Icon(
                Icons.event_seat_outlined,
                color: AppColors.alert,
              ),
              title: const Text('Libérer la table'),
              onTap: () => Navigator.of(sheetContext).pop('release'),
            ),
            ListTile(
              leading: const Icon(
                Icons.edit_outlined,
                color: AppColors.textSecondary,
              ),
              title: const Text('Modifier la table'),
              onTap: () => Navigator.of(sheetContext).pop('edit'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'manage':
        await _goToOrder(table);
      case 'new_addition':
        try {
          await _repository.openAdditionalOrder(table.id);
          await _goToOrder(table);
        } on ApiException catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        }
      case 'release':
        try {
          await _repository.releaseTable(table.id);
          _reload();
        } on ApiException catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        }
      case 'edit':
        await _showEditTableDialog(table);
    }
  }

  Future<void> _showCreateTableDialog() async {
    final nameController = TextEditingController();
    final zoneController = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouvelle table'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nom *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: zoneController,
              decoration: const InputDecoration(labelText: 'Zone (facultatif)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: nameController.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(true),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    if (created != true || nameController.text.trim().isEmpty || !mounted) {
      return;
    }
    try {
      await _repository.createTable(
        nameController.text.trim(),
        zone: zoneController.text.trim().isEmpty
            ? null
            : zoneController.text.trim(),
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _showEditTableDialog(RestaurantTable table) async {
    final nameController = TextEditingController(text: table.name);
    final zoneController = TextEditingController(text: table.zone ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Modifier ${table.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nom *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: zoneController,
              decoration: const InputDecoration(labelText: 'Zone (facultatif)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('delete'),
            style: TextButton.styleFrom(foregroundColor: AppColors.alert),
            child: const Text('Supprimer'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: nameController.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop('save'),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    try {
      if (result == 'save') {
        await _repository.updateTable(
          table.id,
          name: nameController.text.trim(),
          zone: zoneController.text.trim().isEmpty
              ? null
              : zoneController.text.trim(),
        );
      } else if (result == 'delete') {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Supprimer ${table.name} ?'),
            content: const Text('Cette action est irréversible.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.alert),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Supprimer'),
              ),
            ],
          ),
        );
        if (confirm != true) return;
        await _repository.deleteTable(table.id);
      }
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tables')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateTableDialog,
        tooltip: 'Nouvelle table',
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<RestaurantTable>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException
                ? (snapshot.error as ApiException).message
                : '${snapshot.error}';
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _reload,
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            );
          }

          final allTables = snapshot.data!;
          if (allTables.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Aucune table configurée.'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _showCreateTableDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Créer une table'),
                  ),
                ],
              ),
            );
          }

          final searched = _search.isEmpty
              ? allTables
              : allTables
                    .where(
                      (t) =>
                          t.name.toLowerCase().contains(_search.toLowerCase()),
                    )
                    .toList();
          final tables = _filter == _kAllFilter
              ? searched
              : searched
                    .where((t) => _statusBucket(t.status) == _filter)
                    .toList();

          final counts = <String, int>{};
          for (final t in allTables) {
            counts.update(
              _statusBucket(t.status),
              (v) => v + 1,
              ifAbsent: () => 1,
            );
          }

          final zones = <String, List<RestaurantTable>>{};
          for (final table in tables) {
            zones.putIfAbsent(table.zone ?? 'Sans zone', () => []).add(table);
          }

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Rechercher une table',
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => _search = value),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('Toutes (${allTables.length})', _kAllFilter),
                      const SizedBox(width: 8),
                      _filterChip('Libres (${counts['free'] ?? 0})', 'free'),
                      const SizedBox(width: 8),
                      _filterChip(
                        'Occupées (${counts['occupied'] ?? 0})',
                        'occupied',
                      ),
                      const SizedBox(width: 8),
                      _filterChip(
                        'À encaisser (${counts['billing'] ?? 0})',
                        'billing',
                      ),
                      const SizedBox(width: 8),
                      _filterChip(
                        'Réservées (${counts['reserved'] ?? 0})',
                        'reserved',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (tables.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Aucune table dans ce filtre.')),
                  ),
                for (final entry in zones.entries) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 130,
                          mainAxisExtent: 108,
                        ),
                    itemCount: entry.value.length,
                    itemBuilder: (context, index) => _TableCard(
                      table: entry.value[index],
                      onTap: () => _onTableTap(entry.value[index]),
                      onLongPress: () =>
                          _showEditTableDialog(entry.value[index]),
                    ),
                  ),
                ],
                const SizedBox(height: 72),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: AppColors.green,
      labelStyle: TextStyle(
        color: selected ? AppColors.white : AppColors.textPrimary,
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.table,
    required this.onTap,
    required this.onLongPress,
  });

  final RestaurantTable table;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  Color get _background {
    switch (table.status) {
      case 'free':
        return AppColors.greenLight;
      case 'billing':
        return AppColors.alertLight;
      case 'reserved':
        return const Color(0xFFE6EEFB);
      default:
        return AppColors.orangeLight;
    }
  }

  Color get _accent {
    switch (table.status) {
      case 'free':
        return AppColors.green;
      case 'billing':
        return AppColors.alert;
      case 'reserved':
        return const Color(0xFF2563EB);
      default:
        return AppColors.orange;
    }
  }

  IconData get _icon {
    switch (table.status) {
      case 'reserved':
        return Icons.event_available;
      case 'billing':
        return Icons.point_of_sale;
      case 'free':
        return Icons.event_seat_outlined;
      default:
        return Icons.event_seat;
    }
  }

  String get _statusLine {
    switch (table.status) {
      case 'free':
        return 'Libre';
      case 'billing':
        return table.currentTotal != null
            ? '${formatAmount(table.currentTotal!)} F'
            : 'À encaisser';
      case 'reserved':
        final t = table.reservation?.reservedAt.toLocal();
        return t != null
            ? 'Réservée ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'
            : 'Réservée';
      default:
        // Plusieurs additions ouvertes : le total agrégé serait ambigu
        // (à quelle addition l'attribuer ?), on affiche leur nombre à la place.
        if (table.openOrderCount > 1) {
          return '${table.openOrderCount} additions';
        }
        if (table.guestCount != null && table.currentTotal != null) {
          return '${table.guestCount} pers. · ${formatAmount(table.currentTotal!)} F';
        }
        if (table.guestCount != null) return '${table.guestCount} pers.';
        if (table.currentTotal != null) {
          return '${formatAmount(table.currentTotal!)} F';
        }
        return 'Occupée';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _background,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icon, color: _accent, size: 26),
              const SizedBox(height: 4),
              Text(
                table.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                _statusLine,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: _accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2 : Vérifier l'analyse statique**

Run: `cd apps/web/flutter && flutter analyze lib/tables/`
Expected: `No issues found!`

- [ ] **Step 3 : Commit**

```bash
git add apps/web/flutter/lib/tables/floor_plan_page.dart
git commit -m "$(cat <<'EOF'
feat(tables): menu d'une table occupée (gérer/nouvelle addition/libérer/modifier)

Modifier la table devient accessible depuis le menu de chaque table (en
plus de l'appui long déjà existant, conservé) — plus découvrable.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 18 : Vérification complète du frontend

**Files:** (aucun — vérification uniquement)

- [ ] **Step 1 : Formater**

Run: `cd apps/web/flutter && dart format lib/tables lib/pos`
Expected: reformatage propre, aucune erreur.

- [ ] **Step 2 : Analyser**

Run: `cd apps/web/flutter && flutter analyze`
Expected: `No issues found!` (les deux avertissements pré-existants `curly_braces_in_flow_control_structures` dans `monthly_line_chart.dart`/`weekly_bar_chart.dart` peuvent rester, non liés à ce travail).

- [ ] **Step 3 : Tester**

Run: `cd apps/web/flutter && flutter test`
Expected: `All tests passed!` — aucune régression sur la suite existante (aucun test dédié à `floor_plan_page.dart`/`table_order_page.dart`/`pos_page.dart` à ce jour, cohérent avec la note de `docs/api/tables.md`).

- [ ] **Step 4 : Builder**

Run: `cd apps/web/flutter && flutter build web --release`
Expected: `√ Built build\web`

- [ ] **Step 5 : Commit s'il y a des changements de formatage**

```bash
git add -A
git status --short
```

Si des fichiers apparaissent (reformatage), commit :

```bash
git commit -m "$(cat <<'EOF'
style: dart format après la refonte Tables/Caisse

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 19 : Tests widget — menu d'une table occupée et écran Caisse-table

**Files:**
- Create: `apps/web/flutter/test/floor_plan_page_test.dart`
- Create: `apps/web/flutter/test/table_order_page_test.dart`

- [ ] **Step 1 : Écrire le test du menu d'une table occupée**

Créer `apps/web/flutter/test/floor_plan_page_test.dart` :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chez_yasmine/tables/floor_plan_page.dart';

void main() {
  // ApiClient lit Supabase.instance de façon synchrone dès la construction
  // des widgets de ce module — même configuration que les autres tests de
  // module (voir reports_page_test.dart).
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
  });

  testWidgets('shows an empty state without crashing when no backend is reachable in test', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: FloorPlanPage(establishmentId: 'est-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tables'), findsOneWidget);
    // Pas de backend en test : le chargement échoue, l'écran affiche son
    // propre état d'erreur avec un bouton Réessayer plutôt que de planter.
    expect(find.text('Réessayer'), findsOneWidget);
  });
}
```

- [ ] **Step 2 : Lancer le test pour vérifier qu'il passe**

Run: `cd apps/web/flutter && flutter test test/floor_plan_page_test.dart`
Expected: PASS.

- [ ] **Step 3 : Écrire le test de l'écran Caisse-table**

Créer `apps/web/flutter/test/table_order_page_test.dart` :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chez_yasmine/api/api_client.dart';
import 'package:chez_yasmine/tables/table_order_page.dart';
import 'package:chez_yasmine/tables/tables_repository.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
  });

  testWidgets('shows an error state without crashing when no backend is reachable in test', (tester) async {
    final repository = TablesRepository(ApiClient(), 'est-1');
    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          repository: repository,
          establishmentId: 'est-1',
          tableId: 'table-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Addition'), findsOneWidget);
    // Pas de backend en test : listOpenOrdersForTable échoue, le corps
    // affiche le message d'erreur plutôt qu'un panier/une grille.
    expect(find.byIcon(Icons.add_box_outlined), findsOneWidget);
  });
}
```

- [ ] **Step 4 : Lancer le test pour vérifier qu'il passe**

Run: `cd apps/web/flutter && flutter test test/table_order_page_test.dart`
Expected: PASS.

- [ ] **Step 5 : Lancer la suite complète**

Run: `cd apps/web/flutter && flutter test`
Expected: `All tests passed!`

- [ ] **Step 6 : Commit**

```bash
git add apps/web/flutter/test/floor_plan_page_test.dart apps/web/flutter/test/table_order_page_test.dart
git commit -m "$(cat <<'EOF'
test(tables): couverture minimale de FloorPlanPage/TableOrderPage sans backend

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 20 : Vérification finale complète (backend + frontend)

**Files:** (aucun — vérification uniquement)

- [ ] **Step 1 : Backend — suite complète**

Run: `cd apps/api/nestjs && npm test && npm run lint && npm run build`
Expected: tous les tests passent, lint propre (hormis les deux warnings pré-existants déjà notés), build réussi.

- [ ] **Step 2 : Frontend — suite complète**

Run: `cd apps/web/flutter && flutter analyze && flutter test && flutter build web --release`
Expected: `No issues found!`, `All tests passed!`, `√ Built build\web`.

- [ ] **Step 3 : Vérifier qu'aucun fichier n'a été oublié**

Run: `git status --short`
Expected: aucun fichier non suivi/modifié en attente (tout doit avoir été commité au fil des tâches précédentes).

- [ ] **Step 4 : Récapitulatif**

Cette tâche ne produit pas de commit — elle confirme que l'ensemble du plan est appliqué et vérifié avant de passer à la suite (déploiement, revue de code, ou test en conditions réelles selon ce que demande l'utilisateur ensuite).
