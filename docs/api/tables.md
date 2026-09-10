# Tables et serveurs — Chez Yasmine

## Routes NestJS

Protégées par `SupabaseJwtGuard` + `PermissionsGuard` + `@RequirePermissions('tables.manage')` :

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

L'encaissement d'une addition passe par la route de vente existante (Phase 7) : `POST /establishments/:id/sales` avec `orderId` + `tableId` + `source: 'table'`.

## Règles d'état

- **Plusieurs additions ouvertes par table sont supportées** : `openTable()` en crée la première (exige la table `free`/`reserved`) ; `openAdditionalOrder()` en ouvre une supplémentaire sur une table déjà `occupied`, sans toucher son statut ; `split()` reste l'autre façon d'en obtenir une seconde (diviser une addition existante). `TablesService.list()` agrège toutes les additions ouvertes d'une table (`openOrderCount`, `currentTotal` = somme, `guestCount` = celui de la plus ancienne).
- `release()` libère une table sans condition : toutes ses additions ouvertes passent `cancelled` (aucune vente, aucun impact stock), la table repasse `free`. Idempotent, aucune confirmation ni vérification de contenu côté serveur (décision utilisateur 2026-09-10).
- `addItem`/`removeItem` échouent si l'addition n'est plus `open` (déjà clôturée).
- Le prix unitaire d'un produit à prix fixe est toujours relu depuis `product.salePrice` — jamais transmis par le client. Un produit à prix variable (Poulets, Poissons, Plats africains) exige `unitPrice` dans le corps de la requête. Ajouter le même produit au même prix incrémente la ligne existante plutôt que d'en créer une nouvelle (`OrdersService.addItem`) ; `PATCH .../items/:itemId` modifie la quantité d'une ligne déjà présente.
- `transfer` exige que la table de destination soit **libre** (sinon `ConflictException`) ; l'ancienne table redevient libre.
- `merge` déplace tous les `OrderItem` de la commande source vers la cible, ferme la source (`status: closed`) et libère sa table — jamais de suppression, l'historique reste consultable.
- La clôture (`SalesService.create` avec `orderId`) vérifie que l'addition est encore `open`, puis dans la même transaction que la vente : ferme l'addition, et ne libère la table que si plus aucune autre addition n'y est ouverte (`SalesService.create`, corrigé le 2026-09-10 pour le multi-addition).

## UI Flutter

[lib/tables/floor_plan_page.dart](../../apps/web/flutter/lib/tables/floor_plan_page.dart) : tables groupées par zone, couleur selon statut. Un tap sur une table occupée ouvre un menu (Gérer les additions / Nouvelle addition / Libérer la table / Modifier la table) plutôt que d'aller directement à l'addition — cohérent avec les menus déjà utilisés pour une table libre/réservée, qui gagnent aussi une entrée « Modifier la table » (en plus de l'appui long existant, conservé). [lib/tables/table_order_page.dart](../../apps/web/flutter/lib/tables/table_order_page.dart) (remplace l'ancien `order_detail_page.dart`) : reprend la grille produits + panier de la Caisse (composants partagés `lib/pos/product_grid.dart`/`lib/pos/cart_panel.dart`), avec un onglet par addition ouverte quand il y en a plusieurs. Chaque ajout/retrait/changement de quantité continue d'appeler le serveur immédiatement (pas de panier local en attente) — voir `docs/superpowers/specs/2026-09-10-table-order-caisse-design.md` pour le raisonnement complet.

**Fusion et division ne sont pas encore exposées dans l'UI** — le backend les supporte et sont testées, mais l'interface (choisir une addition/une table cible parmi plusieurs) est reportée à une prochaine itération pour rester dans un temps raisonnable.

## Vérifications effectuées

- `OrdersService` : testé avec Prisma mocké — 14 tests couvrant l'ouverture (table déjà occupée rejetée), l'ajout d'article (prix toujours relu du produit, jamais du client), le transfert (table cible occupée rejetée, statuts mis à jour des deux tables), la fusion (déplacement des articles, fermeture de la source, libération de sa table), et la division (le cas « même table » ne libère personne, un cas « autre table » exige qu'elle soit libre).
- `SalesService` : 2 tests supplémentaires couvrant le lien avec les additions (rejet si l'addition est déjà clôturée, fermeture de l'addition + libération de la table lors d'un encaissement réussi).
- UI Flutter : `flutter analyze`/`flutter test`/`flutter build web` ✅. Pas de test widget dédié pour cette phase — les écrans sont majoritairement des vues de données déléguant au repository, avec peu de logique conditionnelle propre à isoler (contrairement aux dialogues de paiement/stock).
- **Non vérifié en conditions réelles** : round-trip HTTP complet — même limitation `DATABASE_URL` que les phases précédentes.
