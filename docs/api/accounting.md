# Dépenses / Pertes / Comptabilité — Chez Yasmine

Phase 12 couvre trois modules NestJS indépendants, tous scopés par établissement.

## Routes

```
GET    /establishments/:establishmentId/expenses                (expenses.manage, filtre ?from=&to=)
POST   /establishments/:establishmentId/expenses                (expenses.manage)
PATCH  /establishments/:establishmentId/expenses/:expenseId      (expenses.manage)
DELETE /establishments/:establishmentId/expenses/:expenseId      (expenses.manage)

GET    /establishments/:establishmentId/losses                  (losses.manage)
POST   /establishments/:establishmentId/losses                  (losses.manage)

GET    /establishments/:establishmentId/cash/closings            (cash.manage)
POST   /establishments/:establishmentId/cash/closings            (cash.manage)
```

Les quatre permissions (`expenses.manage`, `losses.manage`, `cash.manage`, en plus de `settings.manage` déjà existant) étaient déjà seedées en Phase 3 mais inutilisées jusqu'ici — leur présence dans le seed a directement dicté le découpage de cette phase.

## Dépenses (`src/expenses/`)

CRUD simple (`label`, `category?`, `amount`, `expenseDate?` — par défaut aujourd'hui, `note?`), scopé par établissement, sans règle métier particulière au-delà de l'isolation multi-tenant habituelle (404 si la dépense n'appartient pas à l'établissement de la route).

## Pertes (`src/losses/`)

**Changement rétroactif important** : jusqu'à la Phase 12, une perte de stock pouvait être saisie via l'endpoint générique de mouvement de stock (`POST .../products/:id/stock-movements`, type `loss`) sans laisser aucune trace comptable exploitable (juste un `StockMovement`, sans motif structuré ni valorisation). Depuis cette phase :

- `CreateStockMovementDto` n'accepte plus `'loss'` (seuls `in`/`out`/`adjustment` restent, à côté de `'sale'` déjà réservé à la caisse depuis la Phase 7) — voir le commentaire sur le DTO.
- `LossesService.create` est le seul chemin restant : il décrémente le stock, écrit le `StockMovement` (`type: 'loss'`) **et** un enregistrement `Loss` (quantité, motif) dans une seule transaction. Idempotent (id client réutilisé, même mécanisme que ventes/mouvements de stock, Phase 9).
- `LossesService.list` calcule une `estimatedValue` (`quantity * purchasePrice`, 0 si le produit n'a pas de prix d'achat renseigné) — c'est la première fois que `purchasePrice` (Phase 5) sert à autre chose qu'un champ d'affichage.
- Le dialogue de saisie manuelle de stock (`lib/stock/stock_movement_dialog.dart`) n'affiche plus « Perte » dans son sélecteur de type ; un nouvel écran dédié (`lib/losses/`) le remplace, avec un sélecteur de produit.

## Clôture de caisse (`src/cash/`)

Le schéma (Phase 3) définit `PointOfSale`/`CashRegister`/`CashClosing`, mais rien ne les gérait jusqu'ici — `Sale.pointOfSaleId` lui-même n'est jamais renseigné par `SalesService.create`. Construire une UI complète multi-caisses maintenant, avant qu'un établissement en ait réellement besoin, aurait été hors de proportion avec cette phase. `CashService.getOrCreateDefaultRegister` crée donc paresseusement un point de vente (« Caisse principale ») et une caisse (« Caisse ») uniques par établissement au premier appel, plutôt que d'exposer un CRUD dédié — décision documentée dans `ARCHITECTURE.md`, réversible sans changer le contrat de la méthode le jour où le multi-caisse sera nécessaire.

`CashService.close` :
- prend `openedAt` (début de la période comptée) et `countedAmount` (comptage physique) ;
- calcule `expectedAmount` = somme des paiements `cash` des ventes non annulées sur la période, **moins** la somme des dépenses enregistrées sur la même période — hypothèse assumée : une dépense est payée depuis la caisse en espèces (`Expense` n'a pas de champ méthode de paiement ; raisonnable pour un maquis-bar, à revoir si ça cesse d'être vrai) ;
- renvoie un champ `difference` calculé (`countedAmount - expectedAmount`), jamais stocké en base (pas de colonne dédiée dans le schéma).

## Correction transverse : sérialisation des `Decimal`

En écrivant les tests de `CashService`, un défaut préexistant dans **toutes** les phases précédentes a été confirmé : `Prisma.Decimal.toJSON()` renvoie une chaîne (`JSON.stringify({ total: new Decimal('1500.5') })` → `{"total":"1500.5"}`), alors que chaque modèle Flutter analyse les montants avec `(json['x'] as num).toDouble()` — qui échoue sur une chaîne. Comme cela n'avait encore jamais pu se déclencher (aucune Phase n'a eu de vrai round-trip HTTP faute de `DATABASE_URL`), le bug était resté invisible malgré 11 phases de développement.

Corrigé une fois pour toutes plutôt que rustiné module par module : `DecimalTransformInterceptor` (`src/common/`), enregistré globalement dans `main.ts`, convertit récursivement tout `Decimal` d'une réponse en nombre JS avant sérialisation. Testé (8 cas : valeur nue, imbriquée dans objets/tableaux, dates/chaînes/null non affectées, intégration de l'intercepteur lui-même).

## Vérifications effectuées

- `ExpensesService` : 5 tests (Prisma mocké) — filtre de dates, 404 sur update/delete hors établissement.
- `LossesService` : 6 tests (Prisma mocké) — rejeu idempotent, produit hors établissement, stock insuffisant rejeté avant écriture, transaction (mouvement + Loss), calcul de `estimatedValue`.
- `CashService` : 5 tests (Prisma mocké) — création paresseuse du registre par défaut, réutilisation, calcul `expectedAmount`/`difference`.
- `DecimalTransformInterceptor` : 8 tests (aucun mock — fonction pure + intégration Nest).
- UI Flutter (`lib/expenses/`, `lib/losses/`, `lib/cash/`) : `flutter analyze`/`flutter test`/`flutter build web` ✅, y compris la validation de formulaire et le repli défensif sur échec réseau (même pattern que Phases 7/11 : erreur affichée, jamais d'exception non interceptée).
- **Non vérifié en conditions réelles** : round-trip HTTP complet — même limitation `DATABASE_URL` que les phases précédentes.
