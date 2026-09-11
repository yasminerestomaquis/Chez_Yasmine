# Achats / Fournisseurs — Chez Yasmine

## Routes NestJS

Protégées par `SupabaseJwtGuard` + `PermissionsGuard` + `@RequirePermissions('purchases.manage')`, **sauf** `GET .../purchases` (lecture seule, `purchases.view` — voir « Correctif » ci-dessous) :

```
GET    /establishments/:establishmentId/suppliers                                                                purchases.manage
POST   /establishments/:establishmentId/suppliers                                                                 purchases.manage
PATCH  /establishments/:establishmentId/suppliers/:supplierId                                                     purchases.manage
DELETE /establishments/:establishmentId/suppliers/:supplierId                                                     purchases.manage

GET    /establishments/:establishmentId/purchases                                                                 purchases.view
GET    /establishments/:establishmentId/purchases/next-order-number?supplierId=   { orderNumber }  — suggestion    purchases.manage
GET    /establishments/:establishmentId/purchases/:purchaseId                                                     purchases.manage
POST   /establishments/:establishmentId/purchases           { supplierId?, orderNumber, orderDate?, items: [{ productId, casesOrdered }] }   purchases.manage
PATCH  /establishments/:establishmentId/purchases/:purchaseId   (même corps que POST — remplace l'intégralité des lignes)   purchases.manage
DELETE /establishments/:establishmentId/purchases/:purchaseId                                                     purchases.manage
POST   /establishments/:establishmentId/purchases/:id/receive   (déprécié, flux hérité)                            purchases.manage
POST   /establishments/:establishmentId/purchases/:id/cancel    (déprécié, flux hérité)                            purchases.manage
```

### Correctif (2026-09-11) — accès en lecture seule à l'Historique pour le Serveur

Demande utilisateur explicite : le Serveur doit pouvoir consulter l'onglet **Historique** d'Achats (commandes déjà enregistrées), sans pouvoir en créer, modifier, supprimer, ni gérer les fournisseurs.

Nouvelle permission `purchases.view`, affectée uniquement à `GET .../purchases` (utilisée par `PurchasingRepository.listPurchases`) à la place de `purchases.manage` ; toutes les autres routes (y compris `GET .../purchases/:purchaseId` et `GET .../suppliers`) restent réservées à `purchases.manage`. `purchases.view` accordée à Serveur et Magasinier (`supabase/seed/001_roles_permissions.sql`).

Côté Flutter, `PurchasesPage`/`PurchaseOrderDetailPage` reçoivent `roleName` et, pour le Serveur (`roleName == 'Serveur'`) :
- `PurchasesPage` : un seul onglet (Historique), pas de `TabBar`, pas de bouton « Fournisseurs », et `_load()` n'appelle plus `listSuppliers()` (réservé à `purchases.manage`, inutile ici — le fournisseur de chaque commande vient déjà de `listPurchases()`).
- `PurchaseOrderDetailPage(readOnly: true)` : pas de boutons Modifier/Supprimer ni de bouton d'ajout de ligne, et `_loadPickerData()` n'appelle plus `listSuppliers()` non plus (uniquement nécessaire pour le sélecteur de fournisseur en édition).

Vérifié : 299/299 tests NestJS, `flutter analyze`/`test`/`build web` ✅ (47/47 tests Flutter).

## Commande par casier (2026-09-09)

Décision explicite de l'utilisateur : le module Achats ne sert désormais qu'aux produits d'une catégorie **à prix par casier** (`Category.hasCasePricing`, ex. Bières, Vins, Sucreries — voir `docs/api/catalog.md`). `PurchasesService.resolveLines` rejette (400) tout produit dont la catégorie n'a pas `hasCasePricing`, ou dont `bottlesPerCase`/`purchasePricePerCase` ne sont pas renseignés dans le Catalogue.

**Le client n'envoie jamais de prix ni de quantité brute** — seulement `productId` et `casesOrdered` (Nbre de casiers commandés). Le serveur dérive tout depuis la fiche produit (jamais depuis le client, même principe que les prix variables du module Caisse) :

```
quantity  (bouteilles, ce qui bouge le stock)      = casesOrdered × Product.bottlesPerCase
unitPrice (prix par bouteille)                     = Product.purchasePricePerCase / Product.bottlesPerCase
Purchase.total                                     = Σ casesOrdered × purchasePricePerCase
```

`PurchaseItem` fige (`casesOrdered`, `bottlesPerCase`, `purchasePricePerCase`) au moment de la commande — jamais recalculé rétroactivement si la fiche produit change ensuite, même principe que `SaleItem.name`.

`orderNumber` (N° de la commande) est une suggestion **par fournisseur** (`GET .../next-order-number?supplierId=`, dernier + 1, ou 1 si aucun), librement éditable et jamais contrainte en unicité côté serveur — l'utilisateur reste maître du numéro affiché.

## Poulets, Poissons, Plats africains : jamais via Achats (décision actée 2026-09-10)

Un essai d'étendre Achats à ces catégories (`Category.hasVariablePricing`) a été construit puis **abandonné sur décision explicite de l'utilisateur** : leur prix d'achat varie trop d'un jour à l'autre pour qu'un simple "dernier prix connu" sur `Product.purchasePrice` donne un bénéfice par catégorie fiable dans les rapports (un achat du mercredi aurait rétroactivement faussé le coût des ventes du lundi et du mardi). `PurchasesService.resolveLines` rejette donc (comme avant cet essai) tout produit dont la catégorie n'a pas `hasCasePricing`.

Le coût de ces catégories est désormais dérivé de la dépense **« Marché »** (déjà existante, saisie au jour le jour — voir `docs/api/expenses.md`), répartie a posteriori entre les ventes de ces 3 catégories au prorata du chiffre d'affaires du jour, dans le module Graphiques — voir `docs/api/charts.md`.

## Le stock entre directement à la création (décision explicite, 2026-09-09)

Contrairement au flux hérité ci-dessous, **`create` fait immédiatement entrer le stock** (incrémente `product.stockQuantity`, écrit un mouvement `in` par ligne) dans la même transaction que la création de la commande — pas d'étape de réception séparée pour ce flux. `Purchase.status` vaut directement `'received'`.

- **Modification** (`update`) : remplace l'intégralité des lignes — annule d'abord l'effet stock des anciennes lignes, revalide et applique les nouvelles (même validation que `create`). Aucune édition partielle ligne par ligne.
- **Suppression** (`remove`) : annule l'effet stock de la commande puis la supprime. La décrémentation est **clampée à 0** plutôt que de faire échouer si une partie du stock a déjà été vendue depuis (même principe que les remboursements de crédit — un ajustement/une correction ne doit pas bloquer sur un désalignement comptable mineur).

## Flux hérité (`pending` → `receive`/`cancel`)

`receive`/`cancel` restent en place, dépréciés, pour les achats `pending` créés avant cette migration (l'ancien flux "achat classique" créait toujours en `pending`, sans passer par le casier). Jamais utilisés par le nouveau flux, qui crée directement en `received`.

## Bénéfices : coût par casier, pas par bouteille (`docs/api/reports.md`)

`effectiveUnitCost()` (`apps/api/nestjs/src/catalog/product-cost.util.ts`, partagé par `ReportsService` et `ChartsService`) utilise `purchasePricePerCase / bottlesPerCase` comme coût pour un produit à prix par casier — jamais `purchasePrice` ("prix d'achat par bouteille"), décision explicite de l'utilisateur. Repli sur `purchasePrice` si la catégorie n'est pas à prix par casier, ou si ces champs ne sont pas encore renseignés.

## UI Flutter

Trois sous-modules ([lib/purchasing/purchases_page.dart](../../apps/web/flutter/lib/purchasing/purchases_page.dart)) :
- **Créer une commande** : Date (éditable, défaut aujourd'hui), N° de la commande (suggéré, éditable), Fournisseur, puis un produit à la fois — vignette photo (reprise du Catalogue), Nbre de bouteilles par casier (non éditable), Nbre de casiers commandés (éditable), Nbre total de bouteilles (calculé) — bouton **Ajouter la commande** qui ajoute la ligne à la commande en cours et bascule sur Liste de commandes.
- **Liste de commandes** : Date/N° de commande (non éditables, reconduits), lignes accumulées avec **vignette photo par ligne** (reprise du Catalogue, même principe que Créer une commande — décision actée 2026-09-10) — nom, prix d'achat par casier, casiers commandés, prix total, totaux en gras, bouton **Créer la commande** qui enregistre réellement côté serveur.
- **Historique** ([lib/purchasing/purchase_order_detail_page.dart](../../apps/web/flutter/lib/purchasing/purchase_order_detail_page.dart)) : liste des commandes enregistrées ; un tap ouvre le détail dans la même présentation (**vignette photo par ligne** ici aussi, chargée depuis une carte `productId → Product` construite au chargement de l'écran, pas seulement les produits actifs — un produit archivé depuis reste illustré), avec modification (mêmes champs, lignes ajoutables/supprimables/éditables) et suppression.

## Montants affichés avec séparateur de milliers (décision actée 2026-09-10)

Tout montant/prix affiché dans l'application (pas seulement ce module) utilise désormais `formatAmount()` (`lib/common/formatting.dart`) plutôt que `toStringAsFixed(0)` brut — ex. `147000` → `147 000`. Jamais appliqué à la valeur initiale d'un champ éditable (`TextEditingController`/`TextFormField` dont le texte doit rester un nombre brut parsable, ex. le montant de paiement pré-rempli en Caisse) ni aux quantités (casiers, bouteilles, articles) — seulement aux montants/prix en FCFA affichés en lecture seule.

[lib/purchasing/suppliers_page.dart](../../apps/web/flutter/lib/purchasing/suppliers_page.dart) : liste + création + modification + suppression (`PATCH`/`DELETE` déjà supportés côté serveur ; suppression toujours possible, `Purchase.supplierId`/`Product.supplierId` en `onDelete: SetNull`).

## Vérifications effectuées

- `PurchasesService` : testé avec Prisma mocké — rejet produit/catégorie hors périmètre casier, calcul quantity/unitPrice/total depuis casesOrdered, entrée en stock immédiate, modification (annule puis réapplique), suppression (clampée à 0), suggestion de N° de commande par fournisseur, flux hérité `receive`/`cancel` inchangé.
- `effectiveUnitCost` : testé via `ReportsService`/`ChartsService` — coût par casier utilisé pour une catégorie `hasCasePricing`, repli sur `purchasePrice` si les champs casier manquent.
- UI Flutter : `flutter analyze`/`flutter test`/`flutter build web` ✅. Pas de test widget dédié pour les 3 sous-modules (écrans majoritairement des vues de données/formulaires déjà couverts côté logique métier par les tests backend).
- **Non vérifié en conditions réelles** : round-trip HTTP complet — même limitation `DATABASE_URL` que les phases précédentes.
