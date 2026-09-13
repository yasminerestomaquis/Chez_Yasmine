# Offline-first et synchronisation — Chez Yasmine

## Principe

```
Client (hors ligne)
  → opération capturée localement (id UUID généré côté client, réutilisé
    comme id de l'entité serveur)
  → file d'attente locale (shared_preferences, une par établissement)
  → retour réseau → POST /establishments/:id/sync { operations: [...] }
  → chaque opération : rejouée via le même service métier que le chemin
    en ligne (SalesService, StockMovementsService) — aucune logique dupliquée
  → id déjà connu ? renvoyé tel quel, jamais réexécuté (idempotence)
```

## Idempotence (prompt maître §27)

La clé de tout le système : **le client génère l'`id` de l'opération, et ce même `id` devient l'`id` de l'entité créée côté serveur** (`Sale.id` ou `StockMovement.id`). `SalesService.create` et `StockMovementsService.create` vérifient en tout premier lieu si une ligne avec cet `id` existe déjà :

```ts
if (dto.id) {
  const existing = await this.prisma.sale.findFirst({ where: { id: dto.id, establishmentId } });
  if (existing) return existing; // rejeu sans toucher au stock ni recréer quoi que ce soit
}
```

Rejouer la même vente ou le même mouvement de stock (retry réseau, synchronisation répétée) ne peut donc **jamais** créer de doublon ni décrémenter le stock deux fois — vérifié par test (`sales.service.spec.ts`, `stock-movements.service.spec.ts`).

## Le moteur de synchronisation (`SyncService`)

`POST /establishments/:establishmentId/sync` accepte un lot (`operations[]`, 1 à 100), chacune `{ id, entityType, deviceId, payload }` avec `entityType` parmi `'sale' | 'stock_movement' | 'expense' | 'loss' | 'purchase' | 'cash_closing'`. Pas de `@RequirePermissions` unique sur la route : un même lot peut mélanger des types d'opérations qui n'exigent pas la même permission (`pos.sell` pour une vente, `stock.manage` pour un mouvement, `losses.manage`, `purchases.manage`, `cash.manage`) — `SyncService` vérifie la permission appropriée **par opération**, sans bloquer le reste du lot si une seule échoue.

Chaque opération est journalisée dans `sync_operations` (créée en Phase 3) avec son statut (`PENDING` → `SYNCING` → `SYNCED` / `FAILED` / `CONFLICT`) et son `attempt_count`. Une opération déjà `SYNCED` est renvoyée immédiatement sans être redispatchée — défense en profondeur en plus de l'idempotence au niveau de l'entité elle-même.

`entityType: 'sale'` couvre à la fois la vente et son paiement (notre modèle `Sale` les combine déjà) — conforme à « création de ventes, enregistrement de paiements » du prompt maître §25 — et sert aussi à l'**encaissement d'une addition de Table** (`payload.orderId`/`tableId`/`source: 'table'`, exactement le même chemin que `SalesService.create`, voir docs/api/tables.md). `entityType: 'stock_movement'` ne couvre que les mouvements manuels (`in`/`out`/`adjustment`), jamais `sale` (réservé au flux caisse) ni `transfer`. `'loss'`/`'purchase'`/`'cash_closing'` (décision actée 2026-09-13) couvrent respectivement Pertes, Achats (commande par casier) et Clôture de caisse — chacun un unique appel de création côté service, rendu idempotent de la même façon (`dto.id` client réutilisé comme id serveur, vérifié en premier).

## Conflits

Une opération qui échoue métier (ex. stock devenu insuffisant entre-temps, paiement invalide) est marquée **`CONFLICT`**, jamais silencieusement ignorée ni acceptée par un « dernier écrit gagne » (interdit par le prompt maître §28). Le message d'erreur est conservé dans le `payload` JSON (`_lastError`) faute de colonne dédiée sur `sync_operations`. Le lot continue de traiter les opérations suivantes même si l'une d'elles échoue.

## Côté Flutter

- `SyncQueueService` ([lib/sync/sync_queue_service.dart](../../apps/web/flutter/lib/sync/sync_queue_service.dart)) : file locale persistée via `shared_preferences`, une par établissement. `enqueue()` ajoute une opération ; `syncAll()` envoie tout le lot en attente. **Testé en conditions réelles** (persistance locale, isolation entre établissements, ordre conservé — 4 tests, sans mock réseau).
- Même distinction partout, dans chaque écran capable de saisie hors ligne (`PosPage._checkout`, `TableOrderPage._checkout`, `StockMovementDialog._submit`, `ExpensesFormTab`, `_RecordLossDialog._submit`, `PurchasesPage._submitOrder`, `CashPage._openClosingDialog`) : une `ApiException` (rejet métier réel, ex. `400`/`409`) n'est **jamais** mise en file (rejouer ne changerait rien) ; toute autre exception (pas de réponse HTTP du tout — coupure réseau) met l'opération en file avec un UUID généré côté client comme clé d'idempotence, puis informe l'utilisateur.
- `CatalogCache` ([lib/catalog/catalog_cache.dart](../../apps/web/flutter/lib/catalog/catalog_cache.dart)) : le dernier catalogue chargé avec succès est mis en cache localement et resservi si un chargement échoue — la caisse et le stock restent consultables hors ligne (prompt maître §25). Les photos elles-mêmes ne sont pas dupliquées dans ce cache : leurs URLs signées passent par le cache HTTP du navigateur / futur service worker (Phase 15).
- `SyncStatusBar` ([lib/sync/sync_status_bar.dart](../../apps/web/flutter/lib/sync/sync_status_bar.dart)) : indicateur ● En ligne / ○ Hors ligne en **rouge** (prompt maître §24, couleur actée 2026-09-13) + nombre d'opérations en attente + synchronisation automatique, sans action de l'utilisateur, au retour de connexion (écoute `connectivity_plus`) ainsi qu'au premier affichage si la file contenait déjà des opérations en attente (session précédente restée hors ligne) — un polling léger (15 s) sert de filet de sécurité en plus de ces deux déclencheurs. Bouton manuel « Synchroniser » toujours disponible en complément. **Montée une seule fois, globalement** (`MaterialApp.builder` dans `main.dart`, via `GlobalSyncContext` qui porte l'établissement courant) plutôt que dupliquée dans chaque écran — visible en haut de n'importe quel module (décision actée 2026-09-13), pas seulement Caisse/Stock/Dépenses comme avant cette date.

## Portée délibérément couverte / non couverte

Couvert (idempotent de bout en bout, `SyncService` + une file locale par établissement) : vente avec paiement (Caisse **et** encaissement d'une addition de Table), mouvement de stock manuel, dépense, perte, commande d'achat par casier, clôture de caisse.

Non couvert, décision délibérée et documentée ici pour ne pas prétendre à une couverture plus large que ce qui est réellement construit :
- **Ouverture de table et prise de commande hors ligne** (créer une `Order`/ajouter un `OrderItem` alors qu'aucune connexion n'a encore permis au serveur de connaître cette table/cette addition) — seul l'**encaissement** d'une addition déjà existante côté serveur est couvert (le cas le plus fréquent d'une coupure réseau : le service a déjà pris la commande normalement, la coupure survient au moment de payer). Étendre à l'ouverture/la prise de commande elle-même demanderait de faire vivre un état de commande entièrement côté client tant qu'aucun aller-retour serveur n'a eu lieu (plusieurs écrans, pas un seul formulaire) — une extension plus large que ce que permet cette itération.
- **Salaires/Paie** : `PayrollService` est une machine à états à plusieurs étapes (`prepare` → `updateLine` → `validate` → `pay` → `cancel`), chacune gardée par une vérification de statut (ex. `pay()` refuse une paie déjà payée) — contrairement à une simple création, rejouer un appel après une réponse perdue en coupure réseau tomberait sur ce garde-fou et remonterait un rejet métier (jamais silencieux), pas une vraie erreur transitoire : nécessiterait une conception dédiée de la reprise, hors périmètre ici.
- **Utilisateurs** : la création d'un compte passe par Supabase Auth (envoi d'un e-mail d'invitation) — une opération intrinsèquement dépendante du réseau, qu'aucune file locale ne peut rendre disponible hors connexion.
- **Catalogue (édition produit)** : l'ajout/la modification d'une photo passe par Supabase Storage (réseau requis). Les champs texte seuls (prix, nom…) seraient, eux, naturellement idempotents pour une mise en file (une mise à jour rejouée aboutit au même état, contrairement à une création) — piste raisonnable pour une itération future, non construite ici pour garder le périmètre cohérent.

## Vérifications effectuées

- Idempotence `SalesService`/`StockMovementsService`/`ExpensesService`/`LossesService`/`PurchasesService`/`CashService` : testée avec Prisma mocké (rejeu sans recréer l'entité ni retoucher le stock).
- `SyncService` : 9 tests (Prisma mocké) — rejeu d'une opération déjà `SYNCED`, refus par permission sans dispatch, dispatch correct vers chacun des six services avec l'id réutilisé, passage en `CONFLICT` sur erreur métier, traitement de tout le lot même si une opération échoue.
- `SyncQueueService` : 4 tests réels (persistance, isolation par établissement, ordre).
- `flutter analyze` et la suite complète de tests Flutter (67 tests, tous les écrans concernés) : passent sans régression après l'extension de la barre de synchronisation et le câblage des nouveaux écrans.
- **Non vérifié en conditions réelles** : le round-trip complet coupure réseau → mise en file → retour réseau → synchronisation contre un vrai backend déployé — même limitation `DATABASE_URL` que les phases précédentes, et la coupure réseau elle-même n'a pas pu être simulée dans cet environnement de développement (pas d'accès à un vrai navigateur avec throttling réseau).
