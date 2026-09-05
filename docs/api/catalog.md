# Catalogue : catégories, produits, photos — Chez Yasmine

## Routes NestJS

Toutes scopées par établissement (convention `:establishmentId`), protégées par `SupabaseJwtGuard` + `PermissionsGuard` + `@RequirePermissions('products.manage')` :

```
GET    /establishments/:establishmentId/categories
POST   /establishments/:establishmentId/categories
PATCH  /establishments/:establishmentId/categories/:categoryId
DELETE /establishments/:establishmentId/categories/:categoryId

GET    /establishments/:establishmentId/products
GET    /establishments/:establishmentId/products/:productId
POST   /establishments/:establishmentId/products
PATCH  /establishments/:establishmentId/products/:productId
DELETE /establishments/:establishmentId/products/:productId

POST   /establishments/:establishmentId/products/:productId/images        (multipart, champ "file")
DELETE /establishments/:establishmentId/products/:productId/images/:imageId
PATCH  /establishments/:establishmentId/products/:productId/images/:imageId  (body: { isPrimary: true })
GET    /establishments/:establishmentId/products/:productId/images/:imageId/url?variant=thumbnail|small|medium|large
```

`UpdateProductDto` exclut volontairement `stockQuantity` — les changements de stock passeront par les mouvements de stock (Phase 6), jamais par une édition directe du produit.

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
- `CategoriesService`/`ProductsService` : logique métier testée avec Prisma mocké (isolation par établissement, rejet d'une référence catégorie/fournisseur d'un autre établissement).
- Formulaire produit Flutter : testé (5 tests) — présence des champs et des 4 boutons photo, aperçu après sélection de l'image générique, validation bloquant la soumission, pré-remplissage en mode édition.
- Bucket Storage + RLS : migration appliquée sur le projet réel, advisor de sécurité vérifié après coup (aucun nouveau finding).
- **Non vérifié en conditions réelles** : l'appel HTTP bout en bout Flutter → NestJS → Supabase (upload réel d'une photo, listing réel des produits) — bloqué par l'absence de `DATABASE_URL` réel pour exécuter l'API NestJS (limitation déjà documentée en Phase 4, `PROJECT_PLAN.md`), et par la limite d'envoi d'e-mails Supabase atteinte pendant cette session (empêchant la création d'un nouveau compte de test confirmé).
