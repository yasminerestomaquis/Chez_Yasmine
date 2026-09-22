# Stock — Chez Yasmine

## Routes NestJS

Protégées par `SupabaseJwtGuard` + `PermissionsGuard`. **Depuis le 2026-09-11**, la lecture (`GET`) exige `stock.view` et la création d'un mouvement exige `stock.manage` — voir « Correctif » ci-dessous :

```
POST /establishments/:establishmentId/products/:productId/stock-movements   { type, quantity, reason? }   stock.manage
GET  /establishments/:establishmentId/products/:productId/stock-movements                                 stock.view
GET  /establishments/:establishmentId/stock/alerts                                                         stock.view
GET  /establishments/:establishmentId/stock/movement-totals                                                stock.view
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

### Filtre par catégorie, tri par stock croissant, totaux de mouvements par vignette (décision actée 2026-09-16)

Demande utilisateur explicite :

- **Filtre catégorie** : `_CategoryFilterField` ouvre un dialogue de sélection **multiple** (`CheckboxListTile` par catégorie) plutôt qu'un simple menu déroulant à choix unique — plusieurs catégories peuvent être cochées à la fois, un produit apparaît dès qu'il appartient à l'une d'elles. Un bouton « Réinitialiser » dans le dialogue et une icône ✕ sur le champ lui-même (visible dès qu'au moins une catégorie est sélectionnée) ramènent au filtre vide (= toutes les catégories, aucun filtre).
- **Tri** : la liste filtrée est désormais triée par ordre **croissant** du stock actuel (`stockQuantity`), remplaçant l'ordre du catalogue — les produits les plus urgents (rupture, stock faible) remontent naturellement en tête.
- **Vignette produit** : la mention « (seuil X) » à côté de « Stock actuel » est retirée. Trois totaux cumulés apparaissent juste en dessous, dans une rangée structurée à 3 colonnes séparées par un fin trait vertical — **Reçue** (icône verte), **Consommée** (icône orange), **Perte** (icône rouge) — chacun icône + valeur en gras + libellé, la même structure visuelle pour les trois afin de rester lisible d'un coup d'œil.

Nouvelle route `GET .../stock/movement-totals` (`stock.view`) : un seul `groupBy(productId, type)` sur `stock_movements` pour tout l'établissement plutôt qu'un aller-retour par produit (`listForProduct`), puisque le listing affiche potentiellement tout le catalogue en une fois. Mapping délibéré : `in` → reçue, `sale` → consommée, `loss` → perte. **`out` et `adjustment` sont volontairement exclus** : `out` reste une sortie manuelle distincte d'une vente (ex. usage interne) — jamais fusionnée avec « consommée » pour ne pas confondre deux mouvements que l'application distingue déjà partout ailleurs (`stockMovementTypeLabels`) ; `adjustment` est une correction du stock affiché (fixe une valeur absolue, voir `stock-math.ts`), pas un flux réel entré/sorti.

Logique de filtrage/tri extraite en fonctions pures top-level (`stockStatusOf`, `filterAndSortStockProducts`, `lib/stock/stock_page.dart`) — testables sans widget ni réseau, voir `test/stock_page_test.dart`.

## Correctif (2026-09-11) — accès en lecture seule pour le Serveur, sans « Valeur du stock »

Demande utilisateur explicite : le Serveur doit pouvoir consulter tout le module Stock (liste des produits, statut, historique par produit), **sans** créer de mouvement, et **sans** voir la carte « Valeur du stock » (chiffre potentiellement sensible).

Nouvelle permission `stock.view`, affectée aux deux routes `GET` ci-dessus à la place de `stock.manage` (qui reste réservé à la création d'un mouvement) ; note que la liste des produits/leur `stockQuantity` elle-même vient de `GET .../products` (`products.view`, voir `docs/api/catalog.md`), pas d'une route de ce contrôleur. `stock.view` accordée à Serveur et Magasinier (`supabase/seed/001_roles_permissions.sql`).

Côté Flutter, `StockPage` reçoit `roleName` et, pour le Serveur (`roleName == 'Serveur'`) :
- `_StockProductRow(readOnly: true)` retire l'action « Mouvement de stock » du menu par produit ; « Voir l'historique » reste toujours disponible.

Le masquage de « Valeur du stock » par rôle codé en dur ci-dessus est remplacé par une permission dédiée — voir la section suivante.

## Ajout (2026-09-22) — groupe « Valeur du stock » par permission, filtrable par catégorie

Demande utilisateur : le groupe « Valeur du stock » (prix d'achat et prix de vente du stock) ne doit être visible que par le Super Administrateur par défaut, avec la possibilité d'accorder ou de refuser cette visibilité aux autres rôles depuis « Gestion des permissions ».

- **Nouvelle permission `stock.view_value`** (`supabase/seed/001_roles_permissions.sql`), affichée sous Stock > « Mouvements de stock » dans le tableau de « Gestion des permissions » (même regroupement générique par préfixe que les autres permissions `stock.*`, `lib/users/permission_grouping.dart` n'a rien de spécifique à ajouter). Exclue des règles « tout sauf » de Super Administrateur/Administrateur/Propriétaire/Gérant ; accordée explicitement au seul Super Administrateur.
- **`GET .../stock/permissions`** (`stock.view`, même principe que `ChartsController.myPermissions`) : renvoie `{ permissions: string[] }`, filtré aux codes `stock.*` à bascule client (`src/stock/stock-permissions.ts`, pour l'instant seulement `stock.view_value`).
- Côté Flutter, `StockRepository.getMyPermissions()` appelle cette route ; `StockPage._load()` échoue *fermé* (`catchError` → aucune permission) plutôt qu'ouvert — un chiffre potentiellement sensible reste masqué en cas d'échec réseau, contrairement à `ChartsRepository.getMyPermissions()` qui retombe sur *tout accordé* (graphiques déjà tous visibles avant l'introduction de `charts.*`).
- Le groupe lui-même (`_StockValueBox`) a quitté la rangée de compteurs, qui n'affiche plus qu'Articles suivis/Stock faible/Ruptures sur une seule ligne — il vit dans son propre encadré, avec ses deux vignettes **Prix d'achat**/**Prix de vente** (`stockValueTotals`, `lib/stock/stock_value.dart`) et son propre filtre Catégorie à sélection multiple (`_valueCategoryIds`, indépendant du filtre de la liste de produits).
- Troisième vignette **Nombre total de bouteilles en stock** (`stockBottleCount`) : somme de `stockQuantity` restreinte aux catégories `hasCasePricing` (Bières, Vins, Sucreries) — délibérément indépendante de `_valueCategoryIds`, jamais influencée par le filtre Catégorie du groupe (une catégorie à prix variable ou fixe, ex. Gbêlê/Poulets, n'a pas de notion de « bouteille »).

Tests : 2 NestJS (`stock-permissions.spec.ts`).

`ReportsPage` (lien « Voir le stock » des Points d'attention) reçoit désormais aussi `roleName`, uniquement pour le transmettre à `StockPage` en cas de navigation depuis ce lien.

Vérifié : `flutter analyze`/`test`/`build web` ✅ (47/47 tests Flutter, inchangés — pas de nouveau test dédié, le chemin conditionnel étant directement lisible dans `StockPage`).

## Vérifications effectuées

- `stock-math.ts` : **testé en conditions réelles** (fonctions pures, sans mock) — 12 tests couvrant chaque type de mouvement, les rejets (stock insuffisant, quantité invalide) et les seuils.
- `StockMovementsService` : testé avec Prisma mocké — refus d'un mouvement invalide *avant* toute écriture, transaction bien invoquée pour un mouvement valide, filtrage correct des alertes.
- UI Flutter : 3 tests widget sur le dialogue de mouvement (libellé par défaut, relabel en mode correction, validation bloquante).
- **Non vérifié en conditions réelles** : round-trip HTTP complet — même limitation `DATABASE_URL` que les Phases 4 et 5.
