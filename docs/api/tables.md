# Tables et serveurs — Chez Yasmine

## Routes NestJS

Protégées par `SupabaseJwtGuard` + `PermissionsGuard` + `@RequirePermissions('tables.manage')` :

```
GET    /establishments/:establishmentId/tables
POST   /establishments/:establishmentId/tables                       { name, zone? }
PATCH  /establishments/:establishmentId/tables/:tableId
DELETE /establishments/:establishmentId/tables/:tableId

POST   /establishments/:establishmentId/tables/:tableId/open
GET    /establishments/:establishmentId/tables/:tableId/order
POST   /establishments/:establishmentId/orders/:orderId/items        { productId, quantity }
DELETE /establishments/:establishmentId/orders/:orderId/items/:itemId
POST   /establishments/:establishmentId/orders/:orderId/transfer     { toTableId }
POST   /establishments/:establishmentId/orders/:orderId/merge        { intoOrderId }
POST   /establishments/:establishmentId/orders/:orderId/split        { itemIds, toTableId }
```

L'encaissement d'une addition passe par la route de vente existante (Phase 7) : `POST /establishments/:id/sales` avec `orderId` + `tableId` + `source: 'table'`.

## Règles d'état

- **Une seule addition ouverte par table**, imposée uniquement par `openTable()` (pas de contrainte au niveau base) — `split()` est l'exception délibérée : diviser une addition entre deux groupes assis à la même table crée volontairement une seconde commande ouverte sur cette table, sans la marquer libre.
- `addItem`/`removeItem` échouent si l'addition n'est plus `open` (déjà clôturée).
- Le prix unitaire appliqué à chaque article est toujours relu depuis `product.salePrice` au moment de l'ajout — jamais transmis par le client.
- `transfer` exige que la table de destination soit **libre** (sinon `ConflictException`) ; l'ancienne table redevient libre.
- `merge` déplace tous les `OrderItem` de la commande source vers la cible, ferme la source (`status: closed`) et libère sa table — jamais de suppression, l'historique reste consultable.
- La clôture (`SalesService.create` avec `orderId`) vérifie que l'addition est encore `open`, puis dans la même transaction que la vente : ferme l'addition et libère la table.

## UI Flutter

[lib/tables/floor_plan_page.dart](../../apps/web/flutter/lib/tables/floor_plan_page.dart) : tables groupées par zone, couleur selon statut (vert = libre, orange = occupée, rouge = à encaisser). Un tap sur une table libre l'ouvre directement ; sur une table occupée, va au détail de l'addition en cours. [lib/tables/order_detail_page.dart](../../apps/web/flutter/lib/tables/order_detail_page.dart) : liste des articles, ajout depuis le catalogue, suppression, encaissement (réutilise le dialogue de paiement de la Phase 7).

**Fusion et division ne sont pas encore exposées dans l'UI** — le backend les supporte et sont testées, mais l'interface (choisir une addition/une table cible parmi plusieurs) est reportée à une prochaine itération pour rester dans un temps raisonnable.

## Vérifications effectuées

- `OrdersService` : testé avec Prisma mocké — 14 tests couvrant l'ouverture (table déjà occupée rejetée), l'ajout d'article (prix toujours relu du produit, jamais du client), le transfert (table cible occupée rejetée, statuts mis à jour des deux tables), la fusion (déplacement des articles, fermeture de la source, libération de sa table), et la division (le cas « même table » ne libère personne, un cas « autre table » exige qu'elle soit libre).
- `SalesService` : 2 tests supplémentaires couvrant le lien avec les additions (rejet si l'addition est déjà clôturée, fermeture de l'addition + libération de la table lors d'un encaissement réussi).
- UI Flutter : `flutter analyze`/`flutter test`/`flutter build web` ✅. Pas de test widget dédié pour cette phase — les écrans sont majoritairement des vues de données déléguant au repository, avec peu de logique conditionnelle propre à isoler (contrairement aux dialogues de paiement/stock).
- **Non vérifié en conditions réelles** : round-trip HTTP complet — même limitation `DATABASE_URL` que les phases précédentes.
