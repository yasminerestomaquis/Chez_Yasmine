# Achats / Fournisseurs — Chez Yasmine

## Routes NestJS

Protégées par `SupabaseJwtGuard` + `PermissionsGuard` + `@RequirePermissions('purchases.manage')` :

```
GET    /establishments/:establishmentId/suppliers
POST   /establishments/:establishmentId/suppliers
PATCH  /establishments/:establishmentId/suppliers/:supplierId
DELETE /establishments/:establishmentId/suppliers/:supplierId

GET    /establishments/:establishmentId/purchases
GET    /establishments/:establishmentId/purchases/:purchaseId
POST   /establishments/:establishmentId/purchases           { supplierId?, items: [{ productId, quantity, unitPrice }] }
POST   /establishments/:establishmentId/purchases/:id/receive
POST   /establishments/:establishmentId/purchases/:id/cancel
```

## Règle métier centrale

**Créer un achat ne touche jamais le stock.** Seule la **réception** (`receive`) incrémente `product.stockQuantity` et écrit un mouvement `in` par ligne (`reason: "Réception achat <id>"`), dans une transaction unique avec le passage de `Purchase.status` à `received`. Une commande passée mais non encore livrée ne doit pas gonfler artificiellement le stock disponible.

- `create` : rejette un fournisseur ou un produit qui n'appartient pas à l'établissement ; calcule `total` côté serveur (`Σ quantity × unitPrice`), jamais transmis tel quel par le client.
- `receive` : rejette si l'achat n'est plus `pending` (déjà reçu ou annulé) — `ConflictException`.
- `cancel` : uniquement possible tant que l'achat est `pending` ; un achat déjà reçu ne peut plus être annulé (il faudrait une perte/un mouvement de stock inverse, hors périmètre de cette phase).

## UI Flutter

[lib/purchasing/purchases_page.dart](../../apps/web/flutter/lib/purchasing/purchases_page.dart) : liste des achats avec statut, boutons Recevoir/Annuler tant qu'en attente. [lib/purchasing/purchase_form_page.dart](../../apps/web/flutter/lib/purchasing/purchase_form_page.dart) : sélection fournisseur (optionnelle) + ajout de lignes produit/quantité/prix d'achat (pré-rempli avec `product.purchasePrice` si connu). [lib/purchasing/suppliers_page.dart](../../apps/web/flutter/lib/purchasing/suppliers_page.dart) : liste + ajout rapide.

## Vérifications effectuées

- `PurchasesService` : testé avec Prisma mocké — 8 tests couvrant le rejet fournisseur/produit hors établissement, le calcul du total, l'absence de mouvement de stock à la création, l'incrémentation correcte par ligne à la réception, le rejet d'une double réception, et le rejet d'une annulation après réception.
- UI Flutter : `flutter analyze`/`flutter test`/`flutter build web` ✅. Pas de test widget dédié pour cette phase (mêmes raisons qu'en Phase 8 : écrans majoritairement des vues de données).
- **Non vérifié en conditions réelles** : round-trip HTTP complet — même limitation `DATABASE_URL` que les phases précédentes.
