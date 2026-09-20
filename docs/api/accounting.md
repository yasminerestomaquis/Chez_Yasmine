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
PATCH  /establishments/:establishmentId/losses/:lossId          (losses.edit — date, produit, quantité, motif)
DELETE /establishments/:establishmentId/losses/:lossId          (losses.edit — restitue la quantité au stock)

`sellAsUnit` (POST/PATCH, optionnel) : pour un produit avec `unitSalePrice`, `false` = Lot (retire quantité × taille du lot lue dans `Product.unit`, valorisé à `salePrice`), `true` = Unité (retire la quantité, valorisé à `unitSalePrice`). Ignoré sans prix à l'unité. Le listing renvoie `sellAsUnit` et `hasUnitPrice`.

`orderNumber` (POST/PATCH) : obligatoire pour un produit dont la catégorie a `hasCasePricing` ; doit désigner une commande (Achats) contenant le produit. `GET .../losses/order-numbers/:productId` renvoie `{required, options, defaultOrderNumber}`. Le mouvement de stock 'loss' reçoit le motif `Commande n°X — …`, ce qui impute la perte au lot de cette commande.

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

**Modifier/supprimer une perte, listing par date, auteur (décision actée 2026-09-20)** :
- Nouvelle permission **`losses.edit`** (Super Administrateur, Gérant, Serveur uniquement — Administrateur/Propriétaire/Magasinier ne l'ont pas ; exclue de la règle « accès complet », réglable ensuite dans « Gestion des permissions »). Sur `PATCH`/`DELETE`, elle remplace `losses.manage` de la classe (`getAllAndOverride`). Rejouée en production : vérifié, seuls ces 3 rôles la portent.
- `PATCH` change date, produit, quantité et/ou motif. Le stock suit dans une transaction : l'ancienne quantité est restituée au produit d'origine, la nouvelle est retirée du produit choisi (`applyStockMovement`, refus 400 si stock insuffisant), et le `StockMovement` de type `loss` correspondant est mis à jour (produit, quantité, motif, date) pour que les lots FIFO de Graphiques > Stock restent cohérents. `Loss` et son mouvement n'ont pas de clé étrangère commune : ils sont retrouvés par produit + quantité + auteur + horodatage à ±10 s (créés dans la même transaction) ; si aucun mouvement n'est retrouvé (données anciennes), un nouveau est créé. `DELETE` restitue la quantité au stock et supprime les deux enregistrements. Une notification d'activité est émise (« Perte modifiée »/« Perte supprimée »).
- Flutter (`lib/losses/`) : la liste des pertes se filtre par **date choisie** (aujourd'hui par défaut, icône calendrier, « Toutes les dates » pour tout voir) ; au-dessus, en gras, le **nombre total de pertes** et le **montant total** du jour affiché (`lossesOnDay`/`lossTotals`, logique pure). Chaque ligne indique **l'auteur** (`createdByName`, `UserProfile.fullName` renvoyé par `GET .../losses`). Icônes modifier/supprimer visibles pour les rôles portant `losses.edit` (`canEditLosses`, comparaison par nom de rôle comme `canRefundSale`).

**Valeur au prix de vente et date de saisie (décision actée 2026-09-20)** :
- Le listing valorise chaque perte au **prix de vente** du produit (`quantité × Product.salePrice`) et non plus au prix d'achat ; un produit dont le prix se saisit à chaque vente (`salePrice` nul, ex. Gbêlê) retombe sur son `referenceSalePrice`, sinon 0. `GET .../losses` renvoie donc `unitSalePrice` et `estimatedValue` calculé ainsi ; la ligne indique « Prix de vente : … ». **Distinct de Rapports** : `ReportsService.summary` continue de valoriser les pertes au coût (prix d'achat) pour le bénéfice net — le montant de « Voir les pertes » y diffère donc de celui du listing Pertes, volontairement.
- Champ **Date** à l'enregistrement d'une perte, pour les porteurs de `losses.edit` (Super Administrateur/Gérant/Serveur) : `CreateLossDto.createdAt` est appliqué à la perte **et** à son mouvement de stock. Le serveur refuse (403) une date envoyée sans `losses.edit` (`LossesController`, et `SyncService.dispatchLoss` pour la file hors ligne, où la date est alors ignorée) et une date à plus de 24 h dans le futur (400). Sans date, horodatage serveur comme avant.

**Accès accordé au rôle Serveur (décision actée 2026-09-15)** : `losses.manage` ajouté sur demande explicite de l'utilisateur — contrairement à products/stock/purchases, il n'existe pas de `losses.view` séparée (`LossesController` gate `GET`/`POST` avec la même permission), donc un accès en lecture seule n'était pas possible ici : l'octroi est complet (consultation **et** enregistrement d'une perte). `CatalogRepository.listProducts` (sélecteur de produit du dialogue de saisie) fonctionne déjà pour ce rôle via `products.view`, déjà accordé. Rejoué en production (additif, `on conflict do nothing` suffit ici — pas de retrait à faire comme pour `products.manage`/Gérant).

## Clôture de caisse (`src/cash/`)

Le schéma (Phase 3) définit `PointOfSale`/`CashRegister`/`CashClosing`, mais rien ne les gérait jusqu'ici — `Sale.pointOfSaleId` lui-même n'est jamais renseigné par `SalesService.create`. Construire une UI complète multi-caisses maintenant, avant qu'un établissement en ait réellement besoin, aurait été hors de proportion avec cette phase. `CashService.getOrCreateDefaultRegister` crée donc paresseusement un point de vente (« Caisse principale ») et une caisse (« Caisse ») uniques par établissement au premier appel, plutôt que d'exposer un CRUD dédié — décision documentée dans `ARCHITECTURE.md`, réversible sans changer le contrat de la méthode le jour où le multi-caisse sera nécessaire.

`CashService.close` :
- prend `openedAt` (début de la période comptée) et `countedAmount` (comptage physique) ;
- calcule `expectedAmount` = somme des paiements `cash` des ventes non annulées sur la période, **moins** la somme des dépenses enregistrées sur la même période — hypothèse assumée : une dépense est payée depuis la caisse en espèces (`Expense` n'a pas de champ méthode de paiement ; raisonnable pour un maquis-bar, à revoir si ça cesse d'être vrai) ;
- renvoie un champ `difference` calculé (`countedAmount - expectedAmount`), jamais stocké en base (pas de colonne dédiée dans le schéma).

## Correction transverse : sérialisation des `Decimal`

En écrivant les tests de `CashService`, un défaut préexistant dans **toutes** les phases précédentes a été confirmé : `Prisma.Decimal.toJSON()` renvoie une chaîne (`JSON.stringify({ total: new Decimal('1500.5') })` → `{"total":"1500.5"}`), alors que chaque modèle Flutter analyse les montants avec `(json['x'] as num).toDouble()` — qui échoue sur une chaîne. Comme cela n'avait encore jamais pu se déclencher (aucune Phase n'a eu de vrai round-trip HTTP faute de `DATABASE_URL`), le bug était resté invisible malgré 11 phases de développement.

Corrigé une fois pour toutes plutôt que rustiné module par module : `DecimalTransformInterceptor` (`src/common/`), enregistré globalement dans `main.ts`, convertit récursivement tout `Decimal` d'une réponse en nombre JS avant sérialisation. Testé (8 cas : valeur nue, imbriquée dans objets/tableaux, dates/chaînes/null non affectées, intégration de l'intercepteur lui-même).

**Corollaire trouvé le 2026-09-14** (constaté par l'utilisateur : les exports Excel « Boissons vendues » et « Plats vendus » refusaient de s'ouvrir dans Excel, « format ou extension non valide ») : cet intercepteur étant global, il s'appliquait aussi aux réponses binaires (`ReportsService.beveragesSoldExcel`/`platsSoldExcel`, qui renvoient un `Buffer`). Or un `Buffer` est un objet JS (`typeof value === 'object'`) — sans garde-fou, la branche générique le parcourait avec `Object.entries`, qui sur un `Uint8Array` renvoie **une entrée par octet** (`['0', 137]`, `['1', 80]`, ...), remplaçant le fichier binaire par un objet JSON `{"0":137,"1":80,...}`. Le fichier téléchargé gardait le bon nom/la bonne extension (`Content-Disposition` non affecté) mais un contenu totalement invalide — d'où l'erreur Excel, qui décrit exactement ce symptôme. Ce défaut existait depuis l'ajout de l'intercepteur (avant même « Boissons vendues ») ; jamais détecté plus tôt car la seule vérification en production de cette route avant ce jour était un simple `GET` sans authentification (401 attendu, confirmant juste que la route existe) — jamais un téléchargement réel suivi d'une ouverture du fichier. Corrigé par un garde-fou explicite (`Buffer.isBuffer(value)` renvoyé tel quel, avant la branche objet générique) — 1 nouveau test de régression construit autour de la signature ZIP réelle d'un fichier `.xlsx` (`PK\x03\x04`).

## Vérifications effectuées

- `ExpensesService` : 5 tests (Prisma mocké) — filtre de dates, 404 sur update/delete hors établissement.
- `LossesService` : 6 tests (Prisma mocké) — rejeu idempotent, produit hors établissement, stock insuffisant rejeté avant écriture, transaction (mouvement + Loss), calcul de `estimatedValue`.
- `CashService` : 5 tests (Prisma mocké) — création paresseuse du registre par défaut, réutilisation, calcul `expectedAmount`/`difference`.
- `DecimalTransformInterceptor` : 9 tests (aucun mock — fonction pure + intégration Nest), dont le correctif Buffer du 2026-09-14 ci-dessus.
- UI Flutter (`lib/expenses/`, `lib/losses/`, `lib/cash/`) : `flutter analyze`/`flutter test`/`flutter build web` ✅, y compris la validation de formulaire et le repli défensif sur échec réseau (même pattern que Phases 7/11 : erreur affichée, jamais d'exception non interceptée).
- **Non vérifié en conditions réelles** : round-trip HTTP complet — même limitation `DATABASE_URL` que les phases précédentes.
