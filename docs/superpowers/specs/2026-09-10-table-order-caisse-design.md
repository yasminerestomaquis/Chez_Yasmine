# Tables — libération sans condition, multi-additions, écran Caisse-table

Date : 2026-09-10
Statut : approuvé par l'utilisateur, prêt pour plan d'implémentation

## Contexte

Demande utilisateur (verbatim) :

> Dans le module Tables, permets de rendre libre une table occupée sans conditions (un client peut décider de quitter une table sans conditions). Permets de renommer une table ou de la supprimer. A la place de l'interface illustrée en image (image 1) permettant d'ajouter un ou des produits (ou prendre l'addition) sur une table, je préfère l'interface (Caisse) illustrée en image 2. Tiens compte du fait que sur la même table, il peut aussi avoir un ou plusieurs clients (plusieurs additions). Organise les additions (un ou plusieurs encaissements) de manière intelligente. permets de modifier (ou d'ajouter ou de supprimer) un ou plusieurs produits (additions) sur une table.

Image 1 = l'écran actuel d'une addition de table (`OrderDetailPage`) : liste plate d'articles, un `SimpleDialog` texte pour ajouter un produit par son nom.
Image 2 = l'écran Caisse actuel (`PosPage`) : recherche, filtres par catégorie, grille de produits avec photos, panneau panier détaillé.

Renommer/supprimer une table est **déjà implémenté** (`floor_plan_page.dart::_showEditTableDialog`, déclenché par un appui long) — ce spec le rend seulement plus découvrable, il ne réimplémente rien.

## État actuel (constats qui cadrent le design)

- `OrdersService.getOpenOrderForTable` utilise `findFirst` : une seule addition par table peut être récupérée, même si `split()` (mécanisme existant de scission d'addition) en crée déjà plusieurs sur une même table dans un cas précis.
- `PosPage` construit son panier **entièrement en local** (`List<CartLine>`) et n'appelle le serveur qu'à l'encaissement final (`SalesService.createSale`), sans jamais passer par le modèle `Order`/`OrderItem`.
- `OrderDetailPage` (écran de table actuel) persiste **chaque ajout/retrait immédiatement** via `addItem`/`removeItem` — l'addition est donc visible en temps réel par tout autre appareil/le personnel.
- `SalesService.createSale` libère systématiquement la table (`restaurantTable.status = 'free'`) dès qu'une addition liée à une table est payée — **bug latent** pour le multi-addition : si une 2ᵉ addition reste ouverte sur la même table, elle serait ignorée.
- `TablesService.list()` ne récupère qu'une seule addition par table (`take: 1`) pour calculer `currentTotal`/`guestCount` affichés sur la carte de la grille des tables.
- `OrdersService.addItem` refuse explicitement les produits à prix variable (Poulets/Poissons/Plats africains) : *"ajoutez-le depuis la Caisse plutôt que depuis une addition de table"*.
- `Order.status` et `RestaurantTable.status` sont des `String` libres en base (pas d'enum/contrainte CHECK) — une nouvelle valeur de statut (`cancelled`) ne nécessite aucune migration de schéma.

## Décisions actées avec l'utilisateur

1. **Nouvelle addition** : un bouton dédié permet d'ouvrir une addition vierge supplémentaire sur une table déjà occupée, à tout moment — en plus du mécanisme de scission existant, pas à sa place.
2. **Libération forcée** : toutes les additions ouvertes de la table passent au statut `cancelled` (aucune vente enregistrée, aucun impact stock/recettes, trace conservée en base pour historique) ; la table repasse `free`. **Aucune confirmation** n'est demandée côté client.
3. **Architecture panier** : la grille de produits + le style visuel du panier de la Caisse sont réutilisés tels quels sur l'écran de table, mais chaque ajout/retrait/changement de quantité continue d'appeler le serveur immédiatement (persistance immédiate conservée, pas de panier local en attente).
4. **Présentation multi-additions** : onglets en haut de l'écran Caisse-table (« Addition 1 (N) », « Addition 2 (N) », « + ») — on bascule d'une addition à l'autre sans quitter l'écran, chacune avec son propre panier et son propre bouton Encaisser.
5. **Prix variable sur table** : la restriction actuelle est levée — taper sur un produit à prix variable ouvre une saisie de prix (même comportement que la Caisse), puis l'article rejoint l'addition normalement.
6. **Découvrabilité Modifier/Supprimer une table** : en plus de l'appui long existant (conservé), une action « Modifier la table » est ajoutée, visible dans le menu qui s'ouvre au tap — pour toute table, quel que soit son statut.
7. **Menu au tap sur une table occupée** : remplace la navigation directe actuelle vers l'addition. Contenu : **Gérer les additions** (→ écran Caisse-table), **Nouvelle addition**, **Libérer la table**, **Modifier la table**.

## Design détaillé

### Backend (NestJS)

#### Nouveaux endpoints

```
POST   /establishments/:id/tables/:tableId/additions        → ouvre une addition supplémentaire sur une table déjà occupée
GET    /establishments/:id/tables/:tableId/orders            → liste toutes les additions ouvertes d'une table
POST   /establishments/:id/tables/:tableId/release           → libère la table sans condition (annule ses additions ouvertes)
PATCH  /establishments/:id/orders/:orderId/items/:itemId     → modifie la quantité d'un article déjà sur l'addition
```

`POST .../orders/:orderId/items` (existant) accepte désormais un champ optionnel `unitPrice`.

#### `OrdersService`

- `openAdditionalOrder(establishmentId, tableId, serverId, guestCount?)` : exige `table.status === 'occupied'` (contrairement à `openTable`, qui exige `'free'`/`'reserved'`) ; crée un nouvel `Order` sans toucher au statut de la table (déjà `occupied`).
- `listOpenOrdersForTable(establishmentId, tableId)` : remplace `getOpenOrderForTable` — `findMany({ where: { tableId, status: 'open' } })`, chacun avec ses `items`. Lève `NotFoundException` si la table n'a aucune addition ouverte (paritié avec le comportement actuel).
- `release(establishmentId, tableId)` : dans une transaction — `updateMany({ where: { tableId, status: 'open' }, data: { status: 'cancelled', closedAt: now() } })` puis `restaurantTable.update({ status: 'free' })`. Aucune vérification de contenu, aucune exception si la table n'a aucune addition ouverte (idempotent — libérer une table déjà libre ne doit pas planter, mais l'action n'est proposée que sur une table occupée côté UI).
- `updateItemQuantity(establishmentId, orderId, itemId, quantity)` : valide `quantity > 0` (sinon utiliser `removeItem` pour supprimer la ligne — pas de suppression implicite ici, cohérent avec `CreateStockMovementDto`/`applyStockMovement` qui distinguent toujours explicitement les opérations). Vérifie que l'addition est `open` (réutilise `getOpenOrderOrThrow`).
- `addItem` : étendu pour accepter `dto.unitPrice`. Si `product.salePrice == null` (catégorie à prix variable), `dto.unitPrice` devient obligatoire (`BadRequestException` sinon) et sert de prix de ligne ; sinon le prix catalogue prévaut comme aujourd'hui (le champ, s'il est fourni, est ignoré — pas de sous-facturation possible sur un produit à prix fixe). **Fusion par produit** : si l'addition a déjà une ligne pour ce même `productId` (et, pour un produit à prix variable, le même `unitPrice` saisi — deux prix différents pour le même produit restent deux lignes, cas légitime évoqué dans `pos_page.dart`), la quantité de la ligne existante est incrémentée plutôt que de créer une nouvelle ligne — aligne le comportement de l'écran de table sur celui du panier local de la Caisse (`existing.quantity++`).

#### Corrections

- `SalesService.createSale` : après avoir fermé `orderToClose`, ne passer `restaurantTable.status` à `'free'` que si `prisma.order.count({ where: { tableId, status: 'open' } }) === 0` (vérifié dans la même transaction, après la fermeture).
- `TablesService.list()` : retirer `take: 1` sur `orders` ; `currentTotal` devient la somme des totaux de toutes les additions ouvertes ; `guestCount` reste celui de l'addition ouverte la plus ancienne (`orderBy: { openedAt: 'asc' }`, première créée — le nombre de convives n'a pas vocation à se sommer). Expose un nouveau champ `openOrderCount` pour que la carte affiche « 2 additions » plutôt qu'un total ambigu quand il y en a plusieurs.

#### DTOs

- `dto/order-operations.dto.ts` : `AddOrderItemDto` gagne `unitPrice?: number` (`@IsOptional() @IsNumber() @Min(0.01)`). Nouveau `UpdateOrderItemDto { quantity: number }` (`@IsNumber() @Min(0.01)`).

### Frontend (Flutter)

#### `floor_plan_page.dart`

- `_onTableTap` : pour `status == 'occupied'` ou `'billing'`, remplace l'appel direct à `_goToOrder` par un nouveau `_showOccupiedTableActions(table)` (même structure que `_showFreeTableActions`/`_showReservedTableActions`) avec 4 entrées : Gérer les additions → `_goToOrder` (renommé en interne, navigue vers le nouvel écran) ; Nouvelle addition → appelle `openAdditionalOrder` puis navigue directement dans cette addition ; Libérer la table → appelle `release`, `_reload()`, pas de confirmation ; Modifier la table → `_showEditTableDialog` (inchangé).
- `_showFreeTableActions`/`_showReservedTableActions` : ajoutent une entrée « Modifier la table » (→ `_showEditTableDialog`), en plus de l'appui long déjà existant sur la carte (conservé, comportement inchangé).
- `_TableCard`/`_statusLine` : si `table.openOrderCount > 1`, afficher « N additions » au lieu du total agrégé (ambigu sinon).

#### `tables_repository.dart`

- `listOpenOrdersForTable(tableId) → Future<List<OrderDetail>>` (remplace `getOpenOrderForTable`).
- `openAdditionalOrder(tableId, {int? guestCount}) → Future<OrderDetail>`.
- `releaseTable(tableId) → Future<void>`.
- `updateItemQuantity(orderId, itemId, quantity) → Future<void>`.
- `addItem(...)` : ajoute un paramètre optionnel `unitPrice`.

#### Composants Caisse extraits et réutilisés

`pos_page.dart` est scindé : `_ProductGrid`, `_CartPanel`, `_PosProductTile`, `_FloatingCartBar` déménagent vers de nouveaux fichiers partagés (`lib/pos/product_grid.dart`, `lib/pos/cart_panel.dart`) avec une interface générique (liste de lignes de panier affichées + callbacks `onProductTap`/`onChangeQuantity`/`onCheckout`), sans connaissance du fait que l'appelant est `PosPage` (panier local) ou le nouvel écran de table (panier persisté serveur). `PosPage` est mis à jour pour consommer ces composants partagés sans changement de comportement.

#### Nouvel écran `TableOrderPage` (remplace `OrderDetailPage`)

- État : `List<OrderDetail>` (une entrée par addition ouverte) + `int _selectedIndex`.
- En-tête : `TabBar`-like (même pattern que `stock_lots_tab.dart::_tabButton`, soulignement plutôt qu'un vrai `TabBar` imbriqué) avec une entrée par addition (« Addition N (nb articles) ») + un bouton « + » qui appelle `openAdditionalOrder`, ajoute l'addition résultante à la liste et bascule dessus.
- Corps : pour l'addition sélectionnée, réutilise `_ProductGrid`/`_CartPanel` partagés — `onProductTap` appelle `addItem` (avec prompt de prix pour un produit à prix variable, réutilisant `_promptManualPrice` déménagé lui aussi en composant partagé) puis recharge cette addition ; `onChangeQuantity` appelle `updateItemQuantity` (incrément/décrément) ou `removeItem` si la quantité tombe à 0 ; `onCheckout` réutilise le `showPaymentDialog` existant puis `createSale(orderId: ..., tableId: ..., source: 'table')` comme aujourd'hui, et ferme uniquement l'onglet de cette addition (retire de la liste locale ; si c'était la dernière, retour à l'écran Tables).

### Hors périmètre (explicitement non traité par ce spec)

- `transfer`/`merge`/`split` (mécanismes existants de transfert/fusion/scission d'addition) restent inchangés — non mentionnés par la demande. `merge()` a la même classe de bug que celui corrigé dans `SalesService` (libère la table source sans vérifier les autres additions ouvertes) ; non corrigé ici pour rester focalisé, à traiter si le besoin se présente.
- Aucune notification/temps réel (WebSocket) entre plusieurs appareils affichant la même table — la persistance immédiate suffit à ce qu'un rechargement manuel (`_reload()`) montre l'état à jour, comme c'est déjà le cas aujourd'hui.
- Aucune modification du flux Caisse walk-in (`PosPage` reste utilisable sans table, panier local, comportement identique) au-delà de l'extraction de composants partagés.

## Tests à prévoir

- Backend : tests unitaires `OrdersService` (nouvelle addition sur table occupée, refus sur table libre ; libération — annulation multiple, idempotence ; fusion de quantité sur `addItem` répété ; `unitPrice` obligatoire/refusé selon la catégorie ; `updateItemQuantity` refuse une addition fermée) ; `SalesService` (table reste `occupied` si une autre addition reste ouverte après paiement) ; `TablesService.list` (agrégation multi-additions).
- Frontend : tests widget sur le nouveau menu d'une table occupée (4 entrées), l'écran `TableOrderPage` (bascule d'onglet, ajout/retrait, prix variable), non-régression de `PosPage` après extraction des composants partagés.
