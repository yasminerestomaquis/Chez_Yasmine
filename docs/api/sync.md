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

`POST /establishments/:establishmentId/sync` accepte un lot (`operations[]`, 1 à 100), chacune `{ id, entityType: 'sale' | 'stock_movement', deviceId, payload }`. Pas de `@RequirePermissions` unique sur la route : un même lot peut mélanger des types d'opérations qui n'exigent pas la même permission (`pos.sell` pour une vente, `stock.manage` pour un mouvement) — `SyncService` vérifie la permission appropriée **par opération**, sans bloquer le reste du lot si une seule échoue.

Chaque opération est journalisée dans `sync_operations` (créée en Phase 3) avec son statut (`PENDING` → `SYNCING` → `SYNCED` / `FAILED` / `CONFLICT`) et son `attempt_count`. Une opération déjà `SYNCED` est renvoyée immédiatement sans être redispatchée — défense en profondeur en plus de l'idempotence au niveau de l'entité elle-même.

`entityType: 'sale'` couvre à la fois la vente et son paiement (notre modèle `Sale` les combine déjà) — conforme à « création de ventes, enregistrement de paiements » du prompt maître §25. `entityType: 'stock_movement'` ne couvre que les mouvements manuels (`in`/`out`/`adjustment`/`loss`), jamais `sale` (réservé au flux caisse, cf. Phase 6/7) ni `transfer`.

## Conflits

Une opération qui échoue métier (ex. stock devenu insuffisant entre-temps, paiement invalide) est marquée **`CONFLICT`**, jamais silencieusement ignorée ni acceptée par un « dernier écrit gagne » (interdit par le prompt maître §28). Le message d'erreur est conservé dans le `payload` JSON (`_lastError`) faute de colonne dédiée sur `sync_operations`. Le lot continue de traiter les opérations suivantes même si l'une d'elles échoue.

## Côté Flutter

- `SyncQueueService` ([lib/sync/sync_queue_service.dart](../../apps/web/flutter/lib/sync/sync_queue_service.dart)) : file locale persistée via `shared_preferences`, une par établissement. `enqueue()` ajoute une opération ; `syncAll()` envoie tout le lot en attente. **Testé en conditions réelles** (persistance locale, isolation entre établissements, ordre conservé — 4 tests, sans mock réseau).
- `PosPage._checkout` et `StockMovementDialog._submit` : la même distinction partout — une `ApiException` (rejet métier réel, ex. `400`/`409`) n'est **jamais** mise en file (rejouer ne changerait rien) ; toute autre exception (pas de réponse HTTP du tout — coupure réseau) met l'opération en file avec un UUID généré côté client comme clé d'idempotence, puis informe l'utilisateur.
- `CatalogCache` ([lib/catalog/catalog_cache.dart](../../apps/web/flutter/lib/catalog/catalog_cache.dart)) : le dernier catalogue chargé avec succès est mis en cache localement et resservi si un chargement échoue — la caisse et le stock restent consultables hors ligne (prompt maître §25). Les photos elles-mêmes ne sont pas dupliquées dans ce cache : leurs URLs signées passent par le cache HTTP du navigateur / futur service worker (Phase 15).
- `SyncStatusBar` ([lib/sync/sync_status_bar.dart](../../apps/web/flutter/lib/sync/sync_status_bar.dart)) : indicateur ● En ligne / ○ Hors ligne (prompt maître §24) + nombre d'opérations en attente + synchronisation automatique au retour de connexion (écoute `connectivity_plus`) et bouton manuel. Affiché sur les écrans Caisse et Stock.

## Portée délibérément couverte / non couverte

Couvert : vente (avec paiement), mouvement de stock manuel — les deux flux explicitement cités par le prompt maître §25 comme devant fonctionner hors ligne, et déjà idempotents de bout en bout.

Non couvert dans cette itération : ouverture de table et prise de commande hors ligne (Phase 8) — nécessiterait de gérer la création d'une `Order`/l'ajout d'`OrderItem` en file également ; l'architecture du `SyncService` (dispatch par `entityType`) permet de l'ajouter sans refonte, mais l'implémenter maintenant aurait dépassé le temps raisonnable pour cette phase. Documenté ici pour ne pas prétendre à une couverture plus large que ce qui est réellement testé.

## Vérifications effectuées

- Idempotence `SalesService`/`StockMovementsService` : testée avec Prisma mocké (rejeu sans toucher au stock/au produit).
- `SyncService` : 6 tests (Prisma mocké) — rejeu d'une opération déjà `SYNCED`, refus par permission sans dispatch, dispatch correct vers `SalesService`/`StockMovementsService` avec l'id réutilisé, passage en `CONFLICT` sur erreur métier, traitement de tout le lot même si une opération échoue.
- `SyncQueueService` : 4 tests réels (persistance, isolation par établissement, ordre).
- **Non vérifié en conditions réelles** : le round-trip complet coupure réseau → mise en file → retour réseau → synchronisation contre un vrai backend déployé — même limitation `DATABASE_URL` que les phases précédentes, et la coupure réseau elle-même n'a pas pu être simulée dans cet environnement de développement (pas d'accès à un vrai navigateur avec throttling réseau).
