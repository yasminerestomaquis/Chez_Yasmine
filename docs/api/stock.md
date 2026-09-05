# Stock — Chez Yasmine

## Routes NestJS

Protégées par `SupabaseJwtGuard` + `PermissionsGuard` + `@RequirePermissions('stock.manage')` :

```
POST /establishments/:establishmentId/products/:productId/stock-movements   { type, quantity, reason? }
GET  /establishments/:establishmentId/products/:productId/stock-movements
GET  /establishments/:establishmentId/stock/alerts
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

## Vérifications effectuées

- `stock-math.ts` : **testé en conditions réelles** (fonctions pures, sans mock) — 12 tests couvrant chaque type de mouvement, les rejets (stock insuffisant, quantité invalide) et les seuils.
- `StockMovementsService` : testé avec Prisma mocké — refus d'un mouvement invalide *avant* toute écriture, transaction bien invoquée pour un mouvement valide, filtrage correct des alertes.
- UI Flutter : 3 tests widget sur le dialogue de mouvement (libellé par défaut, relabel en mode correction, validation bloquante).
- **Non vérifié en conditions réelles** : round-trip HTTP complet — même limitation `DATABASE_URL` que les Phases 4 et 5.
