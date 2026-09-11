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

## Vérifications effectuées

- Pipeline image (`sharp`) : **testé en conditions réelles** — vraies images générées et traitées en mémoire, 7 tests passants (validation, génération de variantes, non-agrandissement).
- `CategoriesService`/`ProductsService` : logique métier testée avec Prisma mocké (isolation par établissement, rejet d'une référence catégorie/fournisseur d'un autre établissement, suppression physique vs désactivation sur violation de contrainte de clé étrangère (P2003), propagation des autres erreurs Prisma sans les avaler).
- Formulaire produit Flutter : testé (5 tests) — présence des champs et des 4 boutons photo, aperçu après sélection de l'image générique, validation bloquant la soumission, pré-remplissage en mode édition.
- Bucket Storage + RLS : migration appliquée sur le projet réel, advisor de sécurité vérifié après coup (aucun nouveau finding).
- **Non vérifié en conditions réelles** : l'appel HTTP bout en bout Flutter → NestJS → Supabase (upload réel d'une photo, listing réel des produits) — bloqué par l'absence de `DATABASE_URL` réel pour exécuter l'API NestJS (limitation déjà documentée en Phase 4, `PROJECT_PLAN.md`), et par la limite d'envoi d'e-mails Supabase atteinte pendant cette session (empêchant la création d'un nouveau compte de test confirmé).
