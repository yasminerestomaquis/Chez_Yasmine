# Stock — Chez Yasmine

## Routes NestJS

Protégées par `SupabaseJwtGuard` + `PermissionsGuard`. **Depuis le 2026-09-11**, la lecture (`GET`) exige `stock.view` et la création d'un mouvement exige `stock.manage` — voir « Correctif » ci-dessous :

```
POST /establishments/:establishmentId/products/:productId/stock-movements   { type, quantity, reason? }   stock.manage
GET  /establishments/:establishmentId/products/:productId/stock-movements                                 stock.view
GET  /establishments/:establishmentId/stock/alerts                                                         stock.view
```

`type` ∈ `in | out | adjustment | loss`. **`sale` n'est jamais écrit manuellement** — ce type sera produit uniquement par le flux de vente (Phase 7). `transfer` (prévu dans la contrainte `CHECK` de `stock_movements`) attend un vrai support multi-établissement, non traité ici.

## Logique métier

`applyStockMovement` ([apps/api/nestjs/src/stock/stock-math.ts](../../apps/api/nestjs/src/stock/stock-math.ts)) — fonction pure, reprise et adaptée de la règle déjà validée dans le prototype v1 (`docs/superpowers/specs/2026-07-25-maquisbar-pwa-design.md`) :

- `in` additionne, `out`/`loss` soustraient (rejettent si le résultat serait négatif — **"stock insuffisant"**), `adjustment` fixe la quantité directement (c'est une correction d'inventaire, pas un delta).
- Rejette toute quantité négative ou non finie.

`isLowStock(quantity, minStock)` : `minStock` vaut `0` par défaut en base (colonne non nullable) — un seuil à `0` signifie *pas d'alerte configurée*, jamais un déclenchement systématique.

`StockMovementsService.create()` exécute la mise à jour de `products.stock_quantity` et l'insertion de la ligne `StockMovement` **dans une même transaction Prisma** — jamais l'un sans l'autre.

`listLowStockAlerts()` compare deux colonnes du même produit (`stockQuantity` vs `minStock`), ce que l'API `where` de Prisma n'exprime pas nativement pour une comparaison colonne-à-colonne — le filtre `isLowStock` s'applique donc côté application après récupération des produits actifs avec un seuil défini. Adapté à la taille d'un catalogue MVP ; à revoir (requête SQL brute ou vue) si le nombre de produits par établissement devient important.

## UI Flutter

[lib/stock/stock_page.dart](../../apps/web/flutter/lib/stock/stock_page.dart) : bandeau d'alertes en haut (si des produits sont sous leur seuil), liste des produits avec leur stock actuel, et par produit un accès à l'historique et à l'ajout d'un mouvement. [lib/stock/stock_movement_dialog.dart](../../apps/web/flutter/lib/stock/stock_movement_dialog.dart) adapte le libellé du champ quantité selon le type (« Nouvelle quantité totale » pour une correction, « Quantité » sinon). Accessible depuis l'écran d'accueil, à côté du bouton Catalogue.

## Correctif (2026-09-11) — accès en lecture seule pour le Serveur, sans « Valeur du stock »

Demande utilisateur explicite : le Serveur doit pouvoir consulter tout le module Stock (liste des produits, statut, historique par produit), **sans** créer de mouvement, et **sans** voir la carte « Valeur du stock » (chiffre potentiellement sensible).

Nouvelle permission `stock.view`, affectée aux deux routes `GET` ci-dessus à la place de `stock.manage` (qui reste réservé à la création d'un mouvement) ; note que la liste des produits/leur `stockQuantity` elle-même vient de `GET .../products` (`products.view`, voir `docs/api/catalog.md`), pas d'une route de ce contrôleur. `stock.view` accordée à Serveur et Magasinier (`supabase/seed/001_roles_permissions.sql`).

Côté Flutter, `StockPage` reçoit `roleName` et, pour le Serveur (`roleName == 'Serveur'`) :
- `_StockKpiRow` masque la carte « Valeur du stock » (`value: null`) — les 3 autres (Articles suivis/Stock faible/Ruptures) restent visibles.
- `_StockProductRow(readOnly: true)` retire l'action « Mouvement de stock » du menu par produit ; « Voir l'historique » reste toujours disponible.

`ReportsPage` (lien « Voir le stock » des Points d'attention) reçoit désormais aussi `roleName`, uniquement pour le transmettre à `StockPage` en cas de navigation depuis ce lien.

Vérifié : `flutter analyze`/`test`/`build web` ✅ (47/47 tests Flutter, inchangés — pas de nouveau test dédié, le chemin conditionnel étant directement lisible dans `StockPage`).

## Vérifications effectuées

- `stock-math.ts` : **testé en conditions réelles** (fonctions pures, sans mock) — 12 tests couvrant chaque type de mouvement, les rejets (stock insuffisant, quantité invalide) et les seuils.
- `StockMovementsService` : testé avec Prisma mocké — refus d'un mouvement invalide *avant* toute écriture, transaction bien invoquée pour un mouvement valide, filtrage correct des alertes.
- UI Flutter : 3 tests widget sur le dialogue de mouvement (libellé par défaut, relabel en mode correction, validation bloquante).
- **Non vérifié en conditions réelles** : round-trip HTTP complet — même limitation `DATABASE_URL` que les Phases 4 et 5.
