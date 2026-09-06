# Tests complets — Chez Yasmine (Phase 16)

Cette phase ne construit aucune fonctionnalité produit ; elle audite et complète la couverture de tests déjà accumulée phase après phase (Phases 3-15), et referme partiellement l'écart « tests d'intégration » resté ouvert depuis la Phase 4 faute de `DATABASE_URL`.

## Unit tests

### Bilan

- **NestJS** : 161 tests, 25 fichiers, tous passants (`npm run test`).
- **Flutter** : 30 tests, tous passants (`flutter test`).

### Logique métier pure, vérifiée sans mock

`pos-math.ts`/`credit-math.ts` (19 tests, Phase 7), `stock-math.ts` (12 tests, Phase 6), pipeline image (`image-processing.service.spec.ts`, 7 tests avec de vraies images, Phase 5), `DecimalTransformInterceptor` (8 tests, Phase 12), `SyncQueueService` Flutter (4 tests, persistance réelle, Phase 9).

### Lacunes trouvées et comblées dans cette phase

En dressant la liste de tous les services/guards NestJS face à leurs fichiers `.spec.ts`, quatre étaient testés uniquement *indirectement* (via les tests d'autres modules qui les appellent) :

- **`AuthorizationService`** — le service de résolution des permissions RBAC. Notable car le prompt maître cite explicitement « permissions » dans sa liste de tests unitaires attendus (§39), et c'était la seule pièce de cette liste jamais testée directement jusqu'ici. 5 tests ajoutés : union des permissions à travers plusieurs rôles, ensemble vide sans aucun rôle, court-circuit sans requête DB quand aucune permission n'est requise, `hasAllPermissions` vrai/faux.
- **`CustomersService`**, **`SuppliersService`**, **`TablesService`** — CRUD établissement-scopé, testés jusqu'ici seulement par ricochet (ex. `CreditsService` qui appelle `CustomersService` en interne). 4-5 tests chacun, au même niveau de détail que les CRUD déjà testés (`ExpensesService`) : isolation par établissement, 404 sur ressource hors établissement.

`PermissionsGuard` et `SupabaseJwtGuard` avaient déjà leurs propres specs (Phase 4) — ce ne sont pas des lacunes.

## Integration tests

### API / NestJS

Chaque service métier reste testé contre un client Prisma mocké (pattern constant depuis la Phase 5) — un vrai test d'intégration HTTP+Postgres direct depuis NestJS reste bloqué par l'absence de `DATABASE_URL` réel, documentée dans `PROJECT_PLAN.md` depuis la Phase 4 et toujours vraie à ce jour.

### PostgreSQL / Supabase — isolation multi-tenant vérifiée en conditions réelles

Les advisors Supabase (sécurité + performance) avaient déjà été vérifiés en Phase 3/5, mais uniquement de façon *statique* (analyse du schéma et des policies, jamais une requête réelle avec une identité utilisateur simulée). Cette phase a fait tourner un vrai test d'isolation RLS contre le projet Supabase réel, avec nettoyage complet ensuite :

1. Deux comptes (`auth.users`) créés directement en SQL — le trigger `handle_new_user` (Phase 4) s'est déclenché normalement et a provisionné une organisation + un établissement + un profil + un rôle Propriétaire pour chacun, exactement comme lors d'une vraie inscription.
2. Un produit confidentiel inséré dans chacun des deux établissements.
3. **Isolation en lecture** : requête `select * from products` exécutée avec `set local role authenticated` et `set local request.jwt.claims` simulant chaque utilisateur — chacun ne voit que son propre produit, jamais celui de l'autre organisation.
4. **Isolation anonyme** : le rôle `anon` (aucune identité) ne voit aucun des deux produits.
5. **Isolation en écriture** : l'utilisateur A a tenté de modifier le produit de l'utilisateur B (`update products set name = 'PIRATE' where id = ...`) — la requête n'a affecté aucune ligne ; revérifié ensuite avec le rôle `service_role` (qui contourne RLS) que le nom du produit B n'avait pas changé.
6. Toutes les données de test supprimées ; vérifié que `organizations`, `establishments`, `user_profiles`, `products` et `auth.users` sont revenus à zéro ligne.

C'est la première fois que l'isolation multi-tenant est vérifiée par une requête réelle avec une identité simulée, plutôt que par la seule lecture des définitions de policies — un test d'intégration Supabase/PostgreSQL au sens propre du terme, conforme à la demande du prompt maître §39 (« Integration tests : PostgreSQL, Supabase »).

### Advisors re-vérifiés

Aucune nouvelle alerte de sécurité depuis la Phase 3/5 : les deux résultats `WARN` (fonctions `SECURITY DEFINER` appelables en RPC) et les deux `INFO` (`audit_logs`/`sync_operations` : RLS activée sans policy, donc refus par défaut — comportement voulu pour ces tables jamais interrogées par un rôle client) restent les mêmes findings déjà documentés et acceptés dans `ARCHITECTURE.md`. Côté performance, uniquement des `INFO` « index inutilisé » — attendu, la base n'a jamais eu de trafic réel de production.

### Storage / authentification

Déjà vérifiées en conditions réelles lors des phases où elles ont été construites : inscription réelle + vérification SQL (Phase 4), JWT réel émis par une vraie session vérifié via JWKS (Phase 4), upload/traitement de vraies images (Phase 5) — pas repris ici, toujours valables.

## E2E

Les deux scénarios du prompt maître §39 restent **non exécutables de bout en bout** dans cet environnement :

```text
Connexion → création produit → ajout photo → vente → paiement → stock → clôture
Connexion → perte Internet → vente hors ligne → retour Internet → synchronisation → vérification absence de doublon
```

Chacune de leurs étapes est individuellement testée (voir les phases correspondantes), mais un run E2E réel demanderait l'API NestJS effectivement démarrée contre `DATABASE_URL`, ce qui manque depuis la Phase 4. Ne pas fabriquer un E2E « qui passe » sans backend réel derrière (règle de non-fabrication, prompt maître §48) — documenté comme non fait plutôt que simulé.

## Ce qui reste bloqué

Identique à toutes les phases précédentes : `DATABASE_URL` réel manquant empêche (1) de lancer l'API NestJS localement, (2) un vrai round-trip HTTP Flutter → NestJS → Postgres, (3) les scénarios E2E. Le test d'isolation RLS ci-dessus comble une partie du terrain « intégration Postgres/Supabase » sans dépendre de cette pièce manquante, puisqu'il interroge directement la base via les outils MCP Supabase plutôt que via l'API NestJS.
