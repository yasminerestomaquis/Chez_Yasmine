# Catalogue : catégories, produits, photos — Chez Yasmine

## Routes NestJS

Toutes scopées par établissement (convention `:establishmentId`), protégées par `SupabaseJwtGuard` + `PermissionsGuard`. **Depuis le 2026-09-11**, la lecture (`GET`) exige `products.view` et la gestion (création/édition/suppression) exige `products.manage` — deux permissions distinctes (voir « Correctif » ci-dessous) :

```
GET    /establishments/:establishmentId/categories                                                 products.view
POST   /establishments/:establishmentId/categories                                                  products.manage
PATCH  /establishments/:establishmentId/categories/:categoryId                                       products.manage
DELETE /establishments/:establishmentId/categories/:categoryId                                       products.manage

GET    /establishments/:establishmentId/products                                                    products.view
GET    /establishments/:establishmentId/products/:productId                                          products.view
POST   /establishments/:establishmentId/products                                                     products.manage
PATCH  /establishments/:establishmentId/products/:productId                                          products.manage
DELETE /establishments/:establishmentId/products/:productId                                          products.manage

POST   /establishments/:establishmentId/products/:productId/images        (multipart, champ "file")  products.manage
DELETE /establishments/:establishmentId/products/:productId/images/:imageId                          products.manage
PATCH  /establishments/:establishmentId/products/:productId/images/:imageId  (body: { isPrimary: true }) products.manage
GET    /establishments/:establishmentId/products/:productId/images/:imageId/url?variant=...          products.view
```

### Correctif (2026-09-11) — `products.view` séparé de `products.manage`

Avant ce correctif, **toutes** les routes ci-dessus (y compris les `GET` de simple consultation) exigeaient `products.manage`. Or `supabase/seed/001_roles_permissions.sql` n'accorde `products.manage` qu'à Magasinier, Gérant et les rôles d'administration — ni Caissier ni Serveur ne l'ont. Conséquence en conditions réelles : un compte Caissier ou Serveur ne pouvait **pas ouvrir la Caisse** (`PosPage`) ni ajouter un produit à une addition (`TableOrderPage`/`FloorPlanPage`) — les deux listent le catalogue via `CatalogRepository.listProducts`/`listCategories`, qui recevait un 403 dès le premier appel.

Corrigé en introduisant `products.view` (nouvelle permission), affectée sur les routes `GET` ci-dessus à la place de `products.manage`, et accordée à Caissier, Serveur et Magasinier (en plus de `products.manage` pour ce dernier — les deux permissions sont désormais indépendantes, `products.manage` seul ne donne plus le droit de lister). Les rôles à accès complet (Super Administrateur, Administrateur, Propriétaire, Gérant) l'ont automatiquement via leur `cross join permissions`.

`UpdateProductDto` exclut volontairement `stockQuantity` — les changements de stock passeront par les mouvements de stock (Phase 6), jamais par une édition directe du produit.

### Correctif (2026-09-25) — le stock initial à la création génère désormais un mouvement `'in'`

`ProductsService.create` écrivait `product.stockQuantity` depuis `dto.stockQuantity` (champ « Stock initial » du formulaire Flutter) sans jamais créer de `StockMovement` correspondant. Ce stock restait donc invisible pour `computeFifoLots`/`ChartsService.stockLots` (Graphiques > Stock), qui reconstruit les lots exclusivement depuis l'historique des mouvements : la somme des lots d'un produit créé avec un stock initial non nul ne pouvait jamais rejoindre son `stockQuantity` réel — écart constaté en production sur environ 40 % des produits à prix par casier/variable (ex. Bock 66 : stock réel 41, lots 33).

Corrigé : `create` (désormais transactionnel) écrit en plus un mouvement `'in'` (motif « Stock initial à la création du produit », sans N° de commande — ce stock n'a jamais été reçu via Achats) quand `stockQuantity > 0`. Ce mouvement se comporte, pour les catégories gérées par lots (Bières/Vins/Sucreries/Poulets/Poissons/Plats africains), comme tout mouvement sans référence : rattaché au dernier lot visible ou lot synthétique (voir le correctif dans `docs/api/charts.md`). Ne corrige que les produits créés **après** ce déploiement — voir `docs/api/charts.md` pour l'état des produits déjà affectés.

## Suppression : désactivation automatique si le produit a un historique

`ProductsService.remove` (2026-09-08) tente d'abord une suppression physique. `purchase_items.product_id`, `order_items.product_id`, `sale_items.product_id` et `stock_movements.product_id` ne sont **pas** en cascade vers `products` (volontairement — casser l'historique des ventes/achats passés en supprimant un produit serait pire que le garder) : si le produit est référencé par l'un de ces enregistrements, Postgres renvoie une violation de contrainte de clé étrangère (`Prisma.PrismaClientKnownRequestError`, `code: 'P2003'`), que le service intercepte pour **désactiver** le produit (`status: 'inactive'`) à la place plutôt que de laisser échouer la requête. La réponse porte `{ softDeleted: boolean }` pour que l'UI Flutter affiche le bon message (« supprimé » ou « désactivé, ventes/achats existants »). `CategoriesService.remove` n'a pas ce problème : `Product.categoryId` est en `onDelete: SetNull`, donc supprimer une catégorie ne peut jamais échouer — les produits qui y étaient rattachés deviennent simplement sans catégorie.

UI Flutter ([lib/catalog/catalog_page.dart](../../apps/web/flutter/lib/catalog/catalog_page.dart)) : bouton de suppression sur chaque vignette produit (confirmation, puis message adapté selon `softDeleted`), et un dialogue « Gérer les catégories » (icône dans l'AppBar) listant les catégories avec un bouton de suppression chacune.

## Sous-modules par catégorie et catégories à prix variable (2026-09-08)

Le Catalogue affiche désormais une grille de sous-modules — un par catégorie, plus « Sans catégorie » s'il existe des produits sans catégorie — plutôt qu'une liste plate de tous les produits ; un tap ouvre la liste des produits de cette catégorie (UI Flutter : [lib/catalog/catalog_page.dart](../../apps/web/flutter/lib/catalog/catalog_page.dart), `_buildCategoryGrid`/`_buildProductGrid`).

`Category.hasVariablePricing` (migration `20260908220000_add_category_variable_pricing.sql`) marque une catégorie sans prix fixe — décision explicite de l'utilisateur (2026-09-08), initialement pour Poulets, Poissons, Plats africains, mais la liste des catégories reste ouverte : n'importe quelle catégorie peut être basculée en « Prix variable » via la case à cocher du dialogue de création/édition de catégorie (« Gérer les catégories »). Pour un produit dont la catégorie a `hasVariablePricing = true` :

- **Catalogue** : `ProductsService.create`/`update` ignorent silencieusement tout `purchasePrice`/`salePrice` envoyé par le client et les forcent à `null` — jamais de prix fixe stocké. `Product.salePrice` est donc désormais nullable (`UpdateProductDto`/`CreateProductDto` en tiennent compte : `salePrice` optionnel, mais requis côté service si la catégorie n'est *pas* à prix variable, avec `BadRequestException` sinon). Le formulaire Flutter ([lib/catalog/product_form_page.dart](../../apps/web/flutter/lib/catalog/product_form_page.dart)) masque les champs de prix pour ces catégories et affiche une note explicative à la place.
- **Caisse** : le prix de vente se saisit à chaque vente (voir `docs/api/pos.md`), jamais fixé dans le catalogue.
- **Achat** : pas de prix d'achat par produit — le coût correspond à la dépense journalière « Marché » du module Dépenses (voir `docs/api/expenses.md`), qui compte déjà dans le calcul du bénéfice net comme toute autre dépense.
- **Additions de table** : `OrdersService.addItem` rejette (400) l'ajout d'un produit à prix variable — cette UI ne propose pas encore de saisie de prix (contrairement à la Caisse) ; ces produits doivent être vendus depuis la Caisse pour l'instant.
- **Rapports** (`docs/api/reports.md`) : `purchasePrice` nul contribue 0 au coût des marchandises vendues (cogs) par produit — cohérent avec le fait que le coût réel est capté au niveau agrégé via la dépense « Marché », pas par produit.

## Catégories à prix par casier (2026-09-09)

`Category.hasCasePricing` (migration `20260909070000_add_purchase_case_ordering.sql`) marque une catégorie vendue par casier — décision explicite de l'utilisateur, initialement pour Bières, Vins, Sucreries, activable sur n'importe quelle catégorie via la case à cocher « Prix par casier » du dialogue de création/édition (même mécanisme que `hasVariablePricing`, liste ouverte). Pour un produit de ces catégories, le formulaire Flutter ([lib/catalog/product_form_page.dart](../../apps/web/flutter/lib/catalog/product_form_page.dart)) remplace :

- **Référence** par **Nbre de bouteilles par casier** (`Product.bottlesPerCase`, entier) ;
- **Code-barres** par **Prix d'achat par casier** (`Product.purchasePricePerCase`).

Le champ **Prix d'achat** (`Product.purchasePrice`) reste affiché pour ces catégories, seulement relabellisé **« Prix d'achat par bouteille »** dans toute l'UI — mais le calcul du bénéfice (`docs/api/reports.md`) utilise `purchasePricePerCase / bottlesPerCase` à la place pour ces catégories, jamais `purchasePrice` (décision explicite de l'utilisateur). Ces deux champs sont ensuite repris (jamais ressaisis) par le module Achats à chaque commande — voir `docs/api/purchasing.md`.

Ces mêmes catégories peuvent aussi porter un **Prix de vente à l'unité** optionnel (`Product.unitSalePrice`, migration `20260914215024_add_product_unit_sale_price.sql`, décision actée 2026-09-14) : le prix de vente normal (`salePrice`) représente alors un lot (ex. 3 bouteilles à 2 000 FCFA), et ce champ permet aussi la vente d'une seule bouteille à un prix différent (ex. 700 FCFA) — le caissier choisit entre les deux en Caisse/Addition, voir `docs/api/pos.md`.

## Isolation multi-tenant côté NestJS

Prisma se connecte directement à Postgres via `DATABASE_URL` (rôle propriétaire de la base) — **il contourne RLS**, contrairement à un appel PostgREST anon/authenticated. `PermissionsGuard` vérifie l'appartenance à l'établissement, mais chaque requête Prisma des services `CategoriesService`/`ProductsService`/`ProductImagesService` filtre *explicitement* par `establishmentId` — ce n'est jamais automatique à cette couche. `ProductsService` vérifie en plus qu'un `categoryId`/`supplierId` fourni appartient bien au même établissement avant de l'associer à un produit (protection contre le rattachement croisé entre établissements).

## Pipeline photo

```
Upload (Flutter) → validation (MIME + taille + décodage réel) → 4 variantes WebP
  (thumbnail 150px / small 400px / medium 800px / large 1600px, jamais agrandies)
  → upload Supabase Storage (jeton de l'utilisateur, pas service_role)
  → une ligne ProductImage par photo (le storage_path stocké est la base commune
    des 4 variantes, ex. "{org}/{etab}/{produit}/{uuid}" — chaque variante se
    déduit en ajoutant "-{variant}.webp")
```

- `ImageProcessingService` ([apps/api/nestjs/src/storage/image-processing.service.ts](../../apps/api/nestjs/src/storage/image-processing.service.ts)) : validation MIME/taille + décodage réel via `sharp` (ne fait jamais confiance au seul MIME déclaré par le client), génération des 4 variantes. **Testé réellement** (pas de mock) : `image-processing.service.spec.ts` génère de vraies images en mémoire et vérifie le format/dimensions produits.
- `SupabaseStorageService` ([apps/api/nestjs/src/storage/supabase-storage.service.ts](../../apps/api/nestjs/src/storage/supabase-storage.service.ts)) : upload/suppression/URL signée, en s'authentifiant auprès de Supabase Storage avec le jeton **de l'utilisateur** (`request.supabaseAccessToken`, propagé par `SupabaseJwtGuard`) plutôt qu'une clé `service_role` — la RLS de `storage.objects` s'applique donc normalement, sans qu'aucun secret supplémentaire ne soit nécessaire côté NestJS.
- `ProductImagesService`/`ProductImagesController` orchestrent le tout et exposent l'upload multipart (`@UseInterceptors(FileInterceptor('file'))`).

Sélecteur photo côté Flutter ([lib/catalog/product_form_page.dart](../../apps/web/flutter/lib/catalog/product_form_page.dart)), conforme au prompt maître §18 : **Prendre une photo** (`image_picker`, caméra), **Choisir dans la galerie** (`image_picker`, galerie), **Importer un fichier** (`file_picker`, sélecteur de fichiers natif), **Image générique** (asset local `assets/generic_product.png`, uploadée comme une photo normale via le même pipeline).

## URL signées mises en cache côté client (correctif 2026-09-13)

Constaté par l'utilisateur en Caisse : l'affichage des photos produits semblait ralenti par le réseau. Cause identifiée : `CatalogRepository.getImageUrl` (Flutter, `lib/catalog/catalog_repository.dart`) redemandait une URL signée au serveur à **chaque appel**, sans aucun cache — or `PosProductTile` l'appelle dans une `FutureBuilder` reconstruite à **chaque** `setState()` du panier (ajout d'un article, changement de quantité). Résultat : un aller-retour réseau par vignette visible à chaque interaction sur l'écran, pas seulement au premier affichage — nettement plus coûteux qu'un simple chargement d'image.

Corrigé : `getImageUrl` mémorise désormais la `Future<String>` par `(productId, imageId, variant)`, aussi longtemps que vit l'instance de `CatalogRepository` (typiquement toute la durée de vie de l'écran Caisse/Table/Catalogue). Sûr par construction : l'URL signée reste valable 1h côté serveur (`SIGNED_URL_TTL_SECONDS`), et la clé de cache est liée à l'identité de l'image elle-même — un changement d'image principale (`setPrimaryImage`) ne touche jamais l'URL déjà mise en cache d'une image existante, et une nouvelle image porte de toute façon un nouvel id. Un échec (coupure réseau) n'est jamais mis en cache, pour que l'appel suivant réessaie normalement une fois la connexion revenue.

## Gestion retirée au rôle Gérant (décision actée 2026-09-15)

Le Gérant avait `products.manage` par construction (règle générique « tout sauf `roles.manage`/`users.manage` », voir `supabase/seed/001_roles_permissions.sql`) — retiré sur demande explicite de l'utilisateur (« Retire l'accès au Catalogue au rôle Gérant »). `products.view` reste volontairement accordée : le Catalogue est encore consultable, et surtout **Achats en dépend** pour choisir un produit à commander (`PurchaseOrderDetailPage._load` appelle `CatalogRepository.listProducts`) — la retirer aurait aussi cassé Achats pour ce rôle, pas seulement le Catalogue (clarifié avec l'utilisateur avant d'agir).

Rejoué en production (idempotent) : la ligne `role_permissions` existante (Gérant, `products.manage`) a été supprimée explicitement — un seed additif (`on conflict do nothing`) ne peut jamais l'effacer lui-même. Vérifié en base de production : le Gérant ne porte plus que `products.view` pour ce module.

## Catalogue en lecture seule côté client pour les rôles sans `products.manage` (décision actée 2026-09-15)

Constaté par l'utilisateur : le Gérant (et plus largement tout rôle sans `products.manage` — Serveur, Caissier) voyait dans le Catalogue les mêmes boutons créer/modifier/supprimer qu'un rôle pouvant réellement les utiliser, cliquables bien qu'ils échouent en 403 côté serveur. Contrairement à la règle par défaut de l'application (jamais de masquage client selon la permission, un refus serveur suffisant — voir `docs/api/users.md`), le Catalogue fait ici une seconde exception délibérée, comme Utilisateurs avant lui : `CatalogPage._canManage` (comparaison par nom de rôle, faute de code de permission exposé côté client — même limitation que `HomeDashboard._isGerant`/`_isServeur`) vérifie l'appartenance à `{Super Administrateur, Administrateur, Propriétaire, Magasinier}` — les seuls rôles portant réellement `products.manage` en base.

Quand `_canManage` est faux :
- Les icônes « Gérer les catégories »/« Nouvelle catégorie » de l'AppBar et le bouton flottant d'ajout de produit disparaissent.
- Le bouton supprimer de chaque carte produit disparaît (`_ProductCard.onDelete` devient `null`).
- Ouvrir un produit (`ProductFormPage(readOnly: true)`) affiche son nom en titre plutôt que « Modifier le produit », désactive tous les champs et le sélecteur de catégorie, masque les 4 boutons du sélecteur photo et le bouton d'enregistrement — consultation complète des informations du produit, sans aucune action d'écriture possible.
- Les catégories/produits restent listés normalement (grille, badges, prix) — seule la couche de gestion disparaît.

Défense en profondeur seulement : le serveur continue de rejeter (403) toute tentative malgré tout, ce masquage n'est qu'une amélioration d'expérience pour ne pas montrer une action vouée à l'échec.

## Prix de vente saisi à chaque vente pour un produit à catégorie fixe (`requiresPriceAtSale`, décision actée 2026-09-17)

Cas d'usage réel : **Gbêlê**, vendu à un prix qui varie à chaque vente — mais, contrairement à Poulets/Poissons/Plats africains (`hasVariablePricing`), acheté à un **prix connu et fixe par litre**, livré comme n'importe quel produit (entrée de stock normale, pas de numéro de marché à saisir). `Category.hasVariablePricing` ne convenait donc pas : cette catégorie supprime *aussi* le prix d'achat du catalogue et exige un numéro de marché à chaque livraison (voir plus haut) — deux comportements non voulus ici.

`Product.requiresPriceAtSale` (booléen, migration `20260917090000_add_product_manual_sale_price.sql`) résout ce cas au niveau du **produit**, pas de la catégorie :

- **Catalogue** : la catégorie de Gbêlê reste une catégorie à prix fixe ordinaire (`hasVariablePricing = false`) — `unit` vaut `"litre"`, `purchasePrice` (« Prix d'achat par bouteille », réutilisé tel quel) se saisit normalement et sert de coût réel pour les rapports (`effectiveUnitCost`, `docs/api/reports.md`), puisqu'il n'est jamais forcé à `null` par ce mécanisme. Quand `requiresPriceAtSale` est coché dans le formulaire ([lib/catalog/product_form_page.dart](../../apps/web/flutter/lib/catalog/product_form_page.dart)), le champ « Prix de vente (FCFA) * » est remplacé par **Prix de vente initial (référence)** (`Product.referenceSalePrice`) — une valeur purement indicative du stock initial, jamais lue par la caisse, et `salePrice` est forcé à `null` côté serveur (`ProductsService.create`/`update`) quel que soit ce que le client envoie — exactement le même principe de « champ toujours forcé côté service, jamais fait confiance au client » que pour `hasVariablePricing`. Le stock initial lui-même (en litres) utilise le champ **Stock initial** déjà existant à la création d'un produit — aucun nouveau champ nécessaire pour ça.
- **Caisse** : aucun changement de code. `PosPage._addToCart` bascule déjà sur la saisie manuelle du prix dès que `product.salePrice == null` (`SaleItemDto.unitPrice`) — le mécanisme qui fait fonctionner Poulets/Poissons fonctionne donc aussi pour Gbêlê, sans lien avec `category.hasVariablePricing`. C'est cette observation (le vrai déclencheur de la saisie manuelle en caisse est `salePrice == null`, pas le drapeau de catégorie) qui a permis de découpler les deux comportements.
- **Achats/Livraison** : entrée de stock normale, par litre, sans numéro de marché — `requiresPriceAtSale` ne touche à aucune logique de `PurchasesService`/`StockMovement`.
- **Rapports/Graphiques** (`docs/api/reports.md`, `docs/api/charts.md`) : le bénéfice se calcule normalement, `effectiveUnitCost` utilisant `purchasePrice` (connu, fixe) comme coût et `SaleItem.unitPrice` (saisi à la vente) comme recette — aucune allocation pro-rata de type « Marché » nécessaire ici, contrairement à `hasVariablePricing`.

## Compter une boisson hors casier comme "Boissons" dans les rapports (`Category.isBeverage`, décision actée 2026-09-17)

Les listings/exports qui splittent les ventes en "Boissons"/"Plats" (`ReportsService.paymentCategoryBreakdown`/`beveragesSoldExcel`, `CategorySoldItemsPage`, `ReportsPage._showBeveragesSoldListing` — voir `docs/api/reports.md`, `docs/api/pos.md`) ne reconnaissaient jusqu'ici que `hasCasePricing` pour le groupe Boissons. **Gbêlê** (catégorie créée pour `requiresPriceAtSale`, voir ci-dessus) est une boisson mais n'est ni `hasCasePricing` ni `hasVariablePricing` — sans correction, ses ventes auraient disparu de tous les indicateurs "Boissons" (dashboard Accueil compris), sans apparaître non plus dans "Plats".

`Category.isBeverage` (booléen, migration `20260917150000_add_category_is_beverage.sql`) comble ce vide : le critère "compte comme Boissons" devient partout `hasCasePricing || isBeverage` (`Product.isBoissonsGroup` côté Flutter, même expression en ligne côté NestJS). Une catégorie déjà `hasCasePricing` n'a pas besoin de ce drapeau (déjà comptée) — il ne sert que pour une boisson qui, comme Gbêlê, ne rentre dans aucun des deux mécanismes de prix existants. Case à cocher **« Boisson »** ajoutée au dialogue « Gérer les catégories » ([lib/catalog/catalog_page.dart](../../apps/web/flutter/lib/catalog/catalog_page.dart)), à côté de « Prix variable »/« Prix par casier ». Appliqué en production : la catégorie "Gbêlê" existante (créée par l'utilisateur avant ce correctif, avec `hasVariablePricing = true` par erreur — corrigé à `false` à la même occasion, aucune donnée perdue puisque son produit n'avait encore ni prix ni mouvement de stock) porte désormais `isBeverage = true`.

## Vérifications effectuées

- Pipeline image (`sharp`) : **testé en conditions réelles** — vraies images générées et traitées en mémoire, 7 tests passants (validation, génération de variantes, non-agrandissement).
- `CategoriesService`/`ProductsService` : logique métier testée avec Prisma mocké (isolation par établissement, rejet d'une référence catégorie/fournisseur d'un autre établissement, suppression physique vs désactivation sur violation de contrainte de clé étrangère (P2003), propagation des autres erreurs Prisma sans les avaler). `requiresPriceAtSale` (2026-09-17, 5 tests) : salePrice manquant accepté et purchasePrice conservé à la création, salePrice forcé à null même envoyé par le client, referenceSalePrice ignorée quand le drapeau n'est pas actif, salePrice forcé à null dès l'activation du drapeau en édition, referenceSalePrice effacée dès sa désactivation.
- Formulaire produit Flutter : testé (7 tests) — présence des champs et des 4 boutons photo, aperçu après sélection de l'image générique, validation bloquant la soumission, pré-remplissage en mode édition ; `requiresPriceAtSale` (2026-09-17) : la case remplace « Prix de vente » par « Prix de vente initial (référence) » et lève l'obligation de saisie, pré-remplissage de la case et de la valeur de référence en édition.
- `isBeverage` (2026-09-17) : 6 tests Flutter (`catalog_models_test.dart`) — lecture/défaut JSON, `Product.isBoissonsGroup` vrai pour `hasCasePricing` et pour `isBeverage` seul, faux pour `hasVariablePricing` et sans catégorie ; côté serveur voir `docs/api/reports.md` (`paymentCategoryBreakdown`/`beveragesSoldExcel`).
- Bucket Storage + RLS : migration appliquée sur le projet réel, advisor de sécurité vérifié après coup (aucun nouveau finding).
- **Non vérifié en conditions réelles** : l'appel HTTP bout en bout Flutter → NestJS → Supabase (upload réel d'une photo, listing réel des produits) — bloqué par l'absence de `DATABASE_URL` réel pour exécuter l'API NestJS (limitation déjà documentée en Phase 4, `PROJECT_PLAN.md`), et par la limite d'envoi d'e-mails Supabase atteinte pendant cette session (empêchant la création d'un nouveau compte de test confirmé). Le cache d'URL signées ci-dessus est vérifié par lecture de code (`flutter analyze`/`test`/`build web` ✅, 73/73) plutôt que par un test dédié — `CatalogRepository` n'a pas de point d'injection pour un client HTTP simulé (comme aucun autre repository de ce projet, voir `ApiClient`), donc pas de précédent de test réel pour cette classe.
