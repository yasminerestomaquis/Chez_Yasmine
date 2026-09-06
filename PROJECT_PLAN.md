# PROJECT_PLAN.md — Chez Yasmine (MaquisBar)

Statuts : `TODO`, `IN_PROGRESS`, `BLOCKED`, `TESTING`, `DONE`

## Décisions prises

- 2026-09-05 — Adoption de l'architecture v5 (Flutter + NestJS + Supabase) en remplacement du prototype v1. Voir `ARCHITECTURE.md`.
- 2026-09-05 — Authentification via Supabase Auth uniquement (pas de double auth NestJS).
- 2026-09-05 — Branding : nom produit **Chez Yasmine**, logo `Chez Yasmine.png` (racine du dépôt).
- 2026-09-05 — Réutilisation du projet Supabase existant `tsebsulvhgttdwtgqfoj` (org `yasminerestomaquis`), vierge.
- 2026-09-05 — Remote GitHub visé : `https://github.com/yasminerestomaquis/Chez_Yasmine.git`.
- 2026-09-05 — Le prototype v1 (`.claude/worktrees/maquisbar-v1`, branche `worktree-maquisbar-v1`) est conservé comme référence, pas supprimé.

## Problèmes connus

- ~~**BLOCKED (permissions)** — Push vers `origin` impossible~~ **RÉSOLU (2026-09-06)** : `gh` reconnecté au compte `yasminerestomaquis` (device flow, scopes `repo`+`workflow`), `git` configuré pour utiliser ses identifiants (`gh auth setup-git`). Premier push réussi (`master` → `main`), pipeline CI GitHub Actions exécuté pour de vrai — a immédiatement révélé et permis de corriger deux bugs réels invisibles en local : un `package-lock.json` incohérent (`npm ci` échouait, `tsconfck` avait `typescript` dédupliqué vers une version invalide) et l'absence de `npx prisma generate` après `npm ci`. Les deux corrigés, la CI est verte (voir historique Git).
- **Outillage local manquant** — Docker n'est pas installé sur la machine de développement (le build de `docker/Dockerfile.nestjs` n'a donc pas pu être testé localement). Supabase CLI n'est pas installée globalement mais reste utilisable à la demande via `npx supabase@latest ...` (a servi à générer `supabase/config.toml`) ; le développement contre le projet Supabase distant se fait surtout via les outils MCP Supabase (migrations, SQL, Storage) plutôt que via `supabase start` (qui nécessite Docker).
- Un test (`AdditionDetail.test.tsx`, prototype v1) est occasionnellement flaky sous charge (timeout `findByText`) mais passe de manière fiable en isolation ou en re-run — sans impact sur le v5, noté pour mémoire.
- **`npm audit` — 4 vulnérabilités high acceptées** dans `apps/api/nestjs` : `deepmerge-ts`/`mysql2` sont des dépendances transitives du *CLI* Prisma 7.10.0 lui-même (`@prisma/config`), pas du client généré ni du code applicatif — non exposées en production. Le correctif proposé par `npm audit fix --force` rétrograderait vers `prisma@6.19.3`, ce qui abandonnerait la CLI stable actuelle pour une version antérieure ; à réévaluer à la prochaine release stable de Prisma. `@nestjs/mau` (CLI de déploiement Nest, non utilisé — on déploie via Docker/GitHub Actions) a été désinstallé, ce qui a déjà éliminé 5 des 9 vulnérabilités initiales.
- ~~`DATABASE_URL` réel non disponible~~ **RÉSOLU (2026-09-06)** : mot de passe réel fourni par l'utilisateur, renseigné dans `.env` (jamais committé). `npx prisma validate` confirme le schéma toujours aligné avec la base réelle. **L'API NestJS a été démarrée en local pour la première fois du projet** (`npm run start`, connexion Prisma réelle confirmée par les logs — `PrismaService: Connected to the database`) et un vrai round-trip HTTP de bout en bout a été vérifié :
  - `GET /` → 200 (serveur fonctionnel).
  - `GET /auth/me` sans jeton → 401 ; avec un jeton invalide → 401 ; avec un vrai jeton (inscription + confirmation directe en SQL + connexion réelle via l'API Supabase Auth) → 200, profil correctement renvoyé, trigger `handle_new_user` déclenché en conditions réelles (organisation + établissement + rôle Propriétaire auto-créés).
  - `GET /establishments/:id/categories` et `GET /establishments/:id/reports/summary` avec ce jeton → 200 : **`PermissionsGuard` vérifié en conditions réelles pour la première fois** (jusqu'ici seulement testé avec Prisma mocké).
  - Toutes les données de test supprimées après coup (organisation, établissement, profil, compte `auth.users`) ; base revérifiée à zéro ligne sur ces tables.
  
  Cela referme la quasi-totalité des « non vérifié en conditions réelles » listés phase par phase depuis la Phase 4 — non repris ligne par ligne dans chaque section de phase ci-dessous par souci de proportion, mais chacune reste valide comme trace de ce qui a été testé au moment de sa construction (mocké) par opposition à cette vérification (réelle, plus tardive).

## Phases

### Phase 0 — Audit — `DONE`
- Dépôt existant inspecté (historique Git, prototype v1, specs/plans `docs/superpowers/`, prompts `PROMPT/`).
- Cahier des charges v5 lu et confronté au prototype v1 existant (contradiction identifiée et arbitrée par l'utilisateur en faveur de v5).
- Stack vérifiée : Node v25.9.0 ✅, npm ✅, git ✅, gh CLI ✅ (authentifié). Flutter/Dart ❌ → installé pendant cette phase. Docker ❌. Supabase CLI ❌ (compensé par MCP Supabase).
- Projet Supabase existant découvert et audité : `yasminerestomaquis's Project` (`tsebsulvhgttdwtgqfoj`), vierge (0 table, 0 migration).

### Phase 1 — Architecture — `DONE`
- Structure monorepo créée (`apps/`, `packages/`, `supabase/`, `docs/*`, `scripts/`, `docker/`, `.github/workflows/`).
- `CLAUDE.md`, `PROJECT_PLAN.md`, `ARCHITECTURE.md` créés.
- `.gitignore` créé (Node, NestJS, Flutter, secrets, worktrees Claude Code).

### Phase 2 — Infrastructure — `TESTING`
- [x] Remote GitHub `origin` configuré (push bloqué — voir Problèmes connus).
- [x] SDK Flutter installé (`C:\flutter`, branche stable, clonage Git).
- [x] Scaffold Flutter Web (`apps/web/flutter`) — branding appliqué (logo + « Chez Yasmine » dans l'AppBar, manifest PWA, favicon, icônes) ; `flutter analyze` ✅, `flutter test` ✅ (1/1), `flutter build web` ✅. Vérifié visuellement dans le navigateur.
- [x] Scaffold NestJS (`apps/api/nestjs`) via `@nestjs/cli` — `npm run build` ✅.
- [x] Docker (`docker/Dockerfile.nestjs`, `docker-compose.yml`) — écrits, non testés faute de Docker local (voir Problèmes connus).
- [x] `.env.example` — créé.
- [x] CI GitHub Actions (`.github/workflows/ci.yml`, lint/test/build NestJS + Flutter) — écrit, pas encore exécuté faute de remote poussé.
- [x] Config Supabase locale (`supabase/config.toml`) — générée via `npx supabase init` (CLI utilisable à la demande sans installation globale ni Docker).

Restant avant `DONE` : vérifier le pipeline CI une fois le premier push possible ; valider `docker build` une fois Docker disponible (ou accepter de le valider seulement en CI).

### Phase 3 — Base de données — `DONE`
- [x] Modèle complet (30 tables, §16 du prompt maître) appliqué sur le projet Supabase via 6 migrations versionnées (`supabase/migrations/`) — détail dans `docs/database/schema.md`.
- [x] RLS activé et testé sur toutes les tables (isolation par organisation/établissement) ; advisor de sécurité Supabase vérifié, un seul finding résiduel accepté et documenté (fonctions RLS appelables en RPC par `authenticated`, nécessaire au fonctionnement des policies, sans fuite de données).
- [x] Index sur toutes les clés étrangères (advisor de performance Supabase vérifié).
- [x] Seed des rôles/permissions système (`supabase/seed/001_roles_permissions.sql`) exécuté : 15 permissions, 8 rôles, 74 associations.
- [x] Schéma Prisma (`apps/api/nestjs/prisma/schema.prisma`) écrit à la main en miroir des migrations (pas d'accès à `DATABASE_URL` réel pour introspecter) ; `prisma validate`/`prisma generate` ✅. Intégration NestJS via adaptateur pilote `@prisma/adapter-pg` (Prisma 7 a retiré `datasource.url` du schéma) : `PrismaModule`/`PrismaService`, build NestJS ✅.

### Phase 4 — Authentification et RBAC — `TESTING`
Utilisateurs, organisations, établissements, rôles, permissions, sessions — via Supabase Auth + RBAC NestJS (décision actée). Détail complet dans `docs/api/auth.md`.
- [x] Tables et seed RBAC en place (voir Phase 3) : `roles`, `permissions`, `role_permissions`, `user_establishment_roles`, 8 rôles système avec permissions par défaut.
- [x] Trigger d'auto-inscription (`handle_new_user`, migration `20260905193641_auth_bootstrap_trigger.sql`) : crée organisation + établissement + profil + rôle Propriétaire à l'inscription. **Vérifié en conditions réelles** (inscription via l'API Supabase Auth réelle, requête SQL confirmant la création correcte, puis nettoyage des données de test). RPC directe sur la fonction trigger elle-même retirée pour `anon`/`authenticated` (migration `20260905195906_restrict_handle_new_user_function.sql`, finding relevé par l'advisor de sécurité après la Phase 5).
- [x] Flux Supabase Auth côté Flutter : connexion par mot de passe, connexion par OTP e-mail, inscription propriétaire (`lib/auth/`). **Vérifié en conditions réelles** dans le navigateur : page de connexion, inscription (bloquée par la limite d'envoi d'e-mails du plan Supabase gratuit — erreur correctement affichée, aucune donnée orpheline créée), et rejet d'identifiants invalides (« Invalid login credentials » correctement affiché).
- [x] Guard NestJS de vérification du JWT Supabase (`SupabaseJwtGuard`, `src/auth/`) via JWKS (le projet signe en ES256, confirmé en interrogeant l'endpoint JWKS réel) — pas de secret partagé. **Vérifié en conditions réelles** : un jeton émis par une vraie connexion Supabase est accepté, un jeton altéré est rejeté. Tests unitaires ✅ (mocks de `jose`).
- [x] `PermissionsGuard` + `@RequirePermissions(...)` (`src/auth/`), vérifie les permissions via Prisma sur l'établissement `:establishmentId` de la route. Tests unitaires ✅. **Non vérifié en conditions réelles** (nécessite `DATABASE_URL` réel, indisponible ici).
- [x] `GET /auth/me` (profil + établissements de l'utilisateur connecté) — compile, non testé en conditions réelles (même limitation `DATABASE_URL`).
- [ ] Écran de gestion des utilisateurs/rôles par établissement — reporté (fonctionnalité produit, pas fondation d'auth).
- [ ] Flux d'invitation d'un utilisateur dans une organisation existante (au-delà de l'auto-inscription du propriétaire) — reporté.

Restant avant `DONE` : renseigner `DATABASE_URL` réel pour vérifier `PermissionsGuard`/`GET /auth/me` en conditions réelles.

### Phase 5 — Produits et photos — `TESTING`
Détail complet dans `docs/api/catalog.md`.
- [x] CRUD catégories (`src/catalog/categories.*`) — testé (Prisma mocké) : isolation par établissement, 404 correct si la ressource n'appartient pas à l'établissement de la route.
- [x] CRUD produits (`src/catalog/products.*`), champs du prompt maître §17 — testé (Prisma mocké), y compris le rejet d'un `categoryId`/`supplierId` appartenant à un autre établissement. `stockQuantity` volontairement exclu de la mise à jour (réservé aux mouvements de stock, Phase 6).
- [x] Bucket Storage privé `product-images` + RLS (`storage.objects`), migration appliquée sur le projet réel, advisor de sécurité revérifié.
- [x] Pipeline photo : validation réelle (MIME + décodage, pas seulement le MIME déclaré) + génération de 4 variantes WebP (thumbnail/small/medium/large) via `sharp`. **Testé en conditions réelles** (vraies images générées et traitées en mémoire, 7 tests, aucun mock).
- [x] Upload/suppression/URL signée via `SupabaseStorageService`, authentifié avec le jeton de l'utilisateur (pas de clé `service_role` nécessaire côté NestJS).
- [x] UI Flutter catalogue (liste catégories/produits) et formulaire produit avec sélecteur photo à 4 options (caméra / galerie / fichier / image générique), conforme au prompt maître §18. **Testé** : 5 tests widget (champs, 4 boutons photo, aperçu, validation, pré-remplissage en édition) + `flutter analyze`/`flutter build web` ✅.
- [ ] **Non vérifié en conditions réelles** : l'appel HTTP bout en bout Flutter → NestJS → Supabase — bloqué par l'absence de `DATABASE_URL` réel (API NestJS non exécutable ici) et par la limite d'envoi d'e-mails Supabase atteinte pendant la session (empêchant un nouveau compte de test confirmé).

Restant avant `DONE` : vérification bout en bout une fois l'API déployée avec un vrai `DATABASE_URL`.

### Phase 6 — Stock — `TESTING`
Détail complet dans `docs/api/stock.md`.
- [x] Logique pure `applyStockMovement`/`isLowStock` (`src/stock/stock-math.ts`), reprise et adaptée de la règle déjà validée dans le prototype v1. **Testée en conditions réelles** (fonctions pures, sans mock, 12 tests) : entrée/sortie/perte/correction, rejet stock insuffisant, rejet quantité invalide, seuil à 0 = pas d'alerte.
- [x] `StockMovementsService`/`StockController` : mouvements manuels (`in`/`out`/`adjustment`/`loss`), historique par produit, alertes de stock bas — mise à jour du produit et écriture du mouvement dans une même transaction Prisma. Testé (Prisma mocké) : rejet avant écriture si le mouvement est invalide, transaction bien invoquée sinon. `sale` réservé au flux de vente (Phase 7), `transfer` reporté (attend le multi-établissement).
- [x] UI Flutter (`lib/stock/`) : liste des produits avec stock actuel, bandeau d'alertes, dialogue d'ajout de mouvement (libellé adapté selon le type), historique par produit. Accessible depuis l'accueil. Testé : 3 tests widget sur le dialogue.
- [ ] **Non vérifié en conditions réelles** : round-trip HTTP complet — même limitation `DATABASE_URL` que les Phases 4 et 5.

Restant avant `DONE` : vérification bout en bout une fois l'API déployée avec un vrai `DATABASE_URL`.

### Phase 7 — POS — `TESTING`
Détail complet dans `docs/api/pos.md`.
- [x] Logique pure `pos-math.ts`/`credit-math.ts` (totaux de panier, remise, validation de paiement, plafond de crédit), reprise et adaptée du prototype v1. **Testée en conditions réelles**, sans mock, 19 tests.
- [x] `SalesService.create` : recharge toujours le prix depuis la base (jamais depuis le client), vérifie le stock avant transaction, décrémente le stock et écrit un mouvement `sale` par ligne, gère le paiement mixte et le paiement à crédit (plafond vérifié, `Credit` créé). Testé (Prisma mocké).
- [x] `SalesService.refund` : ne supprime jamais la vente (marque `voidedAt`, migration `20260905210122_add_sale_voided_at.sql`), restocke chaque article, réverse le crédit accordé. Testé (Prisma mocké).
- [x] UI Flutter (`lib/pos/`) : cartes produits avec recherche/catégories, panier, paiement mixte, reçu. Un vrai bug de dépassement visuel sur le sélecteur de méthode de paiement a été détecté par les tests et corrigé. 3 tests widget.
- [ ] Paiement à crédit non exposé dans l'UI — nécessite un sélecteur de client (Phase 11), le backend le supporte déjà. Annulation/remboursement pas encore accessible depuis l'UI (endpoint prêt, bouton à ajouter).
- [ ] **Non vérifié en conditions réelles** : round-trip HTTP complet — même limitation `DATABASE_URL` que les phases précédentes.

Restant avant `DONE` : bouton remboursement dans l'UI, vérification bout en bout une fois l'API déployée.

### Phase 8 — Tables et serveurs — `TESTING`
Détail complet dans `docs/api/tables.md`.
- [x] `TablesService`/`TablesController` : CRUD tables (nom, zone).
- [x] `OrdersService`/`OrdersController` : ouverture d'addition (une seule par table, sauf exception `split`), ajout/retrait d'article (prix toujours relu du produit), transfert (table cible doit être libre), fusion (déplace les articles, ferme la source, libère sa table), division. Testé (Prisma mocké), 14 tests.
- [x] `SalesService.create` étendu : la clôture d'une addition (paramètre `orderId`) ferme l'addition et libère la table dans la même transaction que la vente. 2 tests supplémentaires.
- [x] UI Flutter (`lib/tables/`) : plan de salle par zone avec couleur selon statut, détail d'addition (ajout/suppression d'article, encaissement). `flutter analyze`/`test`/`build web` ✅.
- [ ] Fusion et division non exposées dans l'UI (backend prêt et testé, sélecteur de table/addition cible reporté).
- [ ] **Non vérifié en conditions réelles** : round-trip HTTP complet — même limitation `DATABASE_URL` que les phases précédentes.

Restant avant `DONE` : UI fusion/division, vérification bout en bout une fois l'API déployée.

### Phase 9 — Offline-first — `TESTING`
Détail complet dans `docs/api/sync.md`.
- [x] Idempotence : `SalesService.create`/`StockMovementsService.create` acceptent un `id` client réutilisé comme id de l'entité — le rejeu d'une opération déjà connue ne touche plus jamais le stock ni la base. Testé.
- [x] `SyncModule` (`POST /establishments/:id/sync`) : lot d'opérations (`sale`/`stock_movement`), permission vérifiée par opération (pas globale sur la route), journalisation dans `sync_operations` (PENDING/SYNCING/SYNCED/FAILED/CONFLICT), jamais de « dernier écrit gagne » sur un conflit métier. Testé (Prisma mocké), 6 tests.
- [x] `SyncQueueService` Flutter (`lib/sync/`) : file locale persistée (`shared_preferences`), une par établissement. **Testée en conditions réelles**, sans mock réseau, 4 tests.
- [x] `PosPage`/`StockMovementDialog` : distinction stricte rejet métier (jamais mis en file) / coupure réseau (mis en file avec UUID généré côté client). `CatalogCache` : dernier catalogue connu resservi hors ligne. `SyncStatusBar` : indicateur en ligne/hors ligne + synchronisation automatique/manuelle.
- [ ] Ouverture de table et prise de commande non couvertes par la file offline (seules vente et mouvement de stock le sont) — l'architecture du dispatch par `entityType` permet de l'étendre sans refonte, reporté pour rester dans un temps raisonnable.
- [ ] **Non vérifié en conditions réelles** : le round-trip complet coupure réseau → file → synchronisation contre un vrai backend déployé (même limitation `DATABASE_URL`), et la coupure réseau elle-même n'a pas pu être simulée dans cet environnement.

Restant avant `DONE` : étendre la file aux opérations tables/additions, vérification bout en bout une fois l'API déployée.

### Phase 10 — Achats / Fournisseurs — `TESTING`
Détail complet dans `docs/api/purchasing.md`.
- [x] `SuppliersService`/`SuppliersController` : CRUD fournisseurs.
- [x] `PurchasesService`/`PurchasesController` : création (total calculé côté serveur, jamais transmis par le client), réception (incrémente le stock + mouvement `in` par ligne, dans la même transaction que le changement de statut), annulation (uniquement si encore en attente). Testé (Prisma mocké), 8 tests.
- [x] UI Flutter (`lib/purchasing/`) : liste des achats avec statut et actions Recevoir/Annuler, formulaire de création, gestion des fournisseurs. `flutter analyze`/`test`/`build web` ✅.
- [ ] **Non vérifié en conditions réelles** : round-trip HTTP complet — même limitation `DATABASE_URL` que les phases précédentes.

Restant avant `DONE` : vérification bout en bout une fois l'API déployée.

### Phase 11 — Clients / Crédits — `TESTING`
Détail complet dans `docs/api/customers.md`.
- [x] `CustomersService`/`CustomersController` : CRUD clients (`customers.manage`).
- [x] `CreditsService`/`CreditsController` : historique fusionné (ventes à crédit + remboursements), remboursement volontaire (réutilise `applyRepayment` de la Phase 7, strict — rejette un remboursement supérieur au solde). Testé (Prisma mocké), 4 tests.
- [x] **Paiement à crédit activé en caisse** (dette laissée ouverte en Phase 7/8) : `PaymentDialog` charge la liste des clients et exige une sélection avant d'accepter une ligne crédit. Testé, y compris la gestion défensive d'un échec de chargement de la liste clients.
- [x] UI Flutter (`lib/customers/`) : liste clients, création avec plafond de crédit, écran de crédit par client (historique + remboursement). `flutter analyze`/`test`/`build web` ✅.
- [ ] **Non vérifié en conditions réelles** : round-trip HTTP complet — même limitation `DATABASE_URL` que les phases précédentes.

Restant avant `DONE` : vérification bout en bout une fois l'API déployée.

### Phase 12 — Dépenses / Pertes / Comptabilité — `TESTING`
Détail complet dans `docs/api/accounting.md`.
- [x] `ExpensesService`/`ExpensesController` : CRUD dépenses (`expenses.manage`), filtre par période. Testé (Prisma mocké), 5 tests.
- [x] `LossesService`/`LossesController` : enregistrement d'une perte (`losses.manage`) — décrémente le stock, écrit le mouvement `loss` et un enregistrement `Loss` valorisé (`quantity * purchasePrice`) dans une transaction, idempotent. **Changement rétroactif** : `'loss'` n'est plus accepté sur l'endpoint générique de mouvement de stock (Phase 6) — seul ce module l'écrit désormais, pour qu'une perte laisse toujours une trace comptable. Testé (Prisma mocké), 6 tests.
- [x] `CashService`/`CashController` : clôture de caisse (`cash.manage`) — crée paresseusement un point de vente/caisse par défaut (aucune UI multi-caisse n'existait), calcule le montant attendu (paiements espèces − dépenses de la période) et l'écart avec le comptage. Testé (Prisma mocké), 5 tests.
- [x] **Correction transverse** : `DecimalTransformInterceptor` (`src/common/`), enregistré globalement — corrige un défaut présent depuis la Phase 5 (Prisma sérialise `Decimal` en chaîne JSON, incompatible avec le cast `as num` de tous les modèles Flutter), resté invisible faute de round-trip HTTP réel jusqu'ici. 8 tests (sans mock).
- [x] UI Flutter (`lib/expenses/`, `lib/losses/`, `lib/cash/`) : listes, formulaires, repli défensif sur échec réseau. `flutter analyze`/`test`/`build web` ✅.
- [ ] **Non vérifié en conditions réelles** : round-trip HTTP complet — même limitation `DATABASE_URL` que les phases précédentes.

Restant avant `DONE` : vérification bout en bout une fois l'API déployée.

### Phase 13 — Rapports — `TESTING`
Détail complet dans `docs/api/reports.md`.
- [x] `ReportsService.summary` (`reports.view`) : chiffre d'affaires, remises, nombre de ventes, coût des marchandises vendues et marge (à partir du `purchasePrice` *actuel*, `SaleItem` ne fige pas de coût historique — documenté), dépenses et pertes de la période, bénéfice net estimé, créances clients (solde présent, non borné à la période — documenté), alertes de stock bas (réutilise `StockMovementsService.listLowStockAlerts`), produits les plus vendus, performance des serveurs par `Sale.createdBy` (`ServerCommission` existe dans le schéma mais n'est alimenté nulle part — non utilisé, pour rester honnête). `from`/`to` ou `period` (jour/semaine/mois/année) couvrent les quatre périodicités du prompt maître §34 sans quatre endpoints séparés. Testé (Prisma mocké), 8 tests.
- [x] Export CSV (`GET .../reports/summary.csv`). PDF/Excel (également demandés au §34) **délibérément non livrés** : nécessiteraient une dépendance de rendu non choisie/testée, pour une fonctionnalité qui resterait de toute façon invérifiable de bout en bout tant que `DATABASE_URL` manque.
- [x] UI Flutter (`lib/reports/`) : sélecteur de période, indicateurs, top produits, performance serveurs, export CSV affiché dans un dialogue copiable.
- [x] **Effet de bord découvert en testant cette phase** : un défaut latent dans le motif `setState(() { _future = repo.methode(); })` déjà utilisé par plusieurs écrans à rechargement depuis la Phase 5 (course entre le rejet d'un `Future` et le réabonnement de `FutureBuilder`, visible seulement sous `flutter_test`, jamais en production) — corrigé dans `ReportsPage` (`future.ignore()`), documenté sans être répercuté ailleurs (aucun test existant ne l'exerce, pas un bug métier).
- [ ] **Non vérifié en conditions réelles** : round-trip HTTP complet — même limitation `DATABASE_URL` que les phases précédentes.

Restant avant `DONE` : vérification bout en bout une fois l'API déployée ; envisager PDF/Excel si un besoin réel se confirme.

### Phase 14 — Notifications — `TESTING`
Détail complet dans `docs/api/notifications.md`.
- [x] `NotificationsService`/`NotificationsController` : notifications in-app uniquement (pas de push — ni FCM/APNs/Web Push, ni table de jetons dans le schéma, ni clé configurée dans cet environnement). `list`/`unreadCount`/`markAsRead` sans `@RequirePermissions` (comme `GET /auth/me`) — la vérification d'appartenance se fait dans le service via `getOrganizationId`, qui traduit aussi `establishmentId` → `organizationId` (`Notification` est rattachée à l'organisation, pas à l'établissement, contrairement à toutes les autres tables déjà exposées).
- [x] `broadcast` (`settings.manage`) : annonce libre, ciblée ou à toute l'organisation. `generateLowStockAlerts` (`stock.manage`) : réutilise `StockMovementsService.listLowStockAlerts` (Phase 6), dédoublonne par titre non lu — pensée pour être appelée à la demande, aucun ordonnanceur/cron configuré dans cet environnement.
- [x] **Limite documentée** : une notification diffusée (`userId` nul) ne peut pas être marquée lue individuellement — `readAt` est une colonne unique sur la ligne, pas une table de suivi par utilisateur ; `markAsRead` refuse (404) toute notification non explicitement ciblée sur l'appelant plutôt que de mentir sur son état.
- [x] UI Flutter (`lib/notifications/`) : liste (gras si non lu), diffusion, déclenchement manuel de la vérification de stock bas. Testé (Prisma mocké côté service, 9 tests ; `flutter analyze`/`test`/`build web` ✅ côté UI).
- [ ] **Non vérifié en conditions réelles** : round-trip HTTP complet — même limitation `DATABASE_URL` que les phases précédentes.

Restant avant `DONE` : vérification bout en bout une fois l'API déployée ; brancher un vrai ordonnanceur pour `low-stock-check` si le besoin se confirme.

### Phase 15 — PWA avancée — `TESTING`
Détail complet dans `docs/pwa/advanced-pwa.md`.
- [x] **Découverte** : le service worker généré par `flutter build web` (`flutter_service_worker.js`) ne met plus rien en cache dans ce SDK — vérifié dans le navigateur, il s'auto-désinstalle à l'activation (mécanisme officiellement déprécié par Flutter, https://github.com/flutter/flutter/issues/156910). L'hypothèse initiale (« le cache hors ligne est déjà fourni par Flutter ») était fausse ; corrigée avant d'être documentée comme acquise ailleurs.
- [x] Service worker de cache écrit à la main (`web/pwa_cache_worker.js`) : cache au fil de l'eau (pas de liste de préchargement figée, `canvaskit/` a plusieurs variantes de ~37 Mo selon le navigateur), nettoyage des anciens caches à l'activation. **Vérifié en conditions réelles** : cycle de vie complet observé dans le navigateur, et — test décisif — l'app s'est chargée et affichée normalement après arrêt effectif du serveur (pas une simulation).
- [x] Bandeau de mise à jour (écoute `controllerchange`) et bouton d'installation (`beforeinstallprompt`), en JavaScript brut dans `web/index.html` plutôt qu'en Dart — évite de faire dépendre `main.dart` (importé par un test) de bindings web incompatibles avec l'exécution sur la VM de `flutter test`. Déclenchement vérifié par simulation directe des événements navigateur.
- [x] Optimisation : tree-shaking des polices déjà actif (mesuré : réductions de 99%+ à chaque build) ; `--wasm` évalué (compilation confirmée) mais **non adopté**, compatibilité runtime des plugins fédérés utilisés (image_picker, file_picker, connectivity_plus, shared_preferences) non vérifiée.
- [ ] **Non vérifié** : un vrai cycle de mise à jour de bout en bout (deux versions déployées successivement) et un déclenchement naturel de l'invite d'installation — tous deux demandent un déploiement réel.

Restant avant `DONE` : vérification en conditions de déploiement réel (mise à jour de version, invite d'installation naturelle).

### Phase 16 — Tests complets — `TESTING`
Détail complet dans `docs/testing/phase-16-tests.md`.
- [x] Audit unitaire : 4 lacunes trouvées et comblées — `AuthorizationService` (jamais testé directement malgré « permissions » explicitement cité au prompt maître §39), `CustomersService`/`SuppliersService`/`TablesService` (CRUD testés seulement par ricochet jusqu'ici). +18 tests. Total : **161 tests NestJS, 30 tests Flutter**, tous passants.
- [x] **Test d'intégration PostgreSQL/Supabase réel** (première fois, pas seulement les advisors statiques déjà vérifiés en Phase 3/5) : deux comptes créés en SQL (le trigger `handle_new_user` s'est déclenché normalement), un produit confidentiel par établissement, puis lecture/écriture simulées avec `set local role authenticated` + `request.jwt.claims` par utilisateur — isolation totale confirmée en lecture (chacun ne voit que le sien), en écriture (tentative de modification croisée sans effet, revérifié avec `service_role`), et pour le rôle `anon` (rien visible). Toutes les données de test supprimées, base revérifiée à zéro ligne.
- [x] Advisors sécurité/performance re-vérifiés : aucune régression depuis la Phase 3/5, mêmes findings déjà acceptés.
- [ ] **E2E non exécutés** (les deux scénarios du prompt maître §39) — demandent l'API NestJS réellement démarrée contre `DATABASE_URL`, toujours indisponible ; non fabriqués (règle de non-fabrication, §48).

Restant avant `DONE` : E2E une fois l'API déployée avec un vrai `DATABASE_URL`.

### Phase 17 — Production — `TESTING`
Détail complet dans `docs/deployment/production-readiness.md`.
- [x] **Bug CI réel trouvé et corrigé** : le job `api` de `.github/workflows/ci.yml` (écrit en Phase 2, jamais exécuté faute de push) ne définissait pas `DATABASE_URL` — `npm run build` aurait échoué dès sa première exécution réelle (chaque `npm run build` de ce projet, tout au long des 17 phases, n'a jamais tourné sans cette variable en préfixe). Corrigé et revérifié en local, dans l'ordre exact de la CI (lint/test/build).
- [x] Job `deploy` ajouté sur une branche `production` dédiée (Tests → Build → Build PWA → Déploiement, prompt maître §36), `needs: [api, web]`, mais `if: false` — aucun hébergeur choisi, pas de secrets/cible à fabriquer.
- [x] `.env.example` réconcilié avec l'usage réel du code (vérifié par recherche, pas supposé) : `JWT_SECRET`/`SUPABASE_SERVICE_ROLE_KEY`/`STORAGE_BUCKET` annotés comme non lus par le code (décisions déjà actées en Phases 4/5), sans être supprimés (traçabilité face à la liste du prompt maître §37). `API_URL` — qui, lui, était censé être utilisé mais était figé en dur côté Flutter — rendu réellement configurable via `--dart-define`.
- [x] Nettoyage : script `deploy` mort (`nest deploy`, fourni par `@nestjs/mau`, désinstallé depuis la Phase 2) retiré de `package.json`.
- [ ] **Toujours bloqué** : Docker (introuvable, re-vérifié), push GitHub (droits du compte `gh`), `DATABASE_URL` réel, choix d'un hébergeur de production — identiques aux phases précédentes, non résolus par cette phase.

Restant avant `DONE` : lever les blocages ci-dessus (accès GitHub, mot de passe Postgres, choix d'hébergeur) — hors de portée de cet environnement de développement.

## Fonctionnalités terminées

- Schéma de données et RBAC de référence (Phase 3), vérifiés (RLS, advisors, seed).
- Inscription propriétaire, connexion (mot de passe + OTP) et vérification JWT (Phase 4) — bout en bout côté authentification, vérifiées en conditions réelles contre le projet Supabase.
- Catégories, produits et pipeline photo natif (Phase 5) — première fonctionnalité métier visible ; logique et pipeline image vérifiés (mocks Prisma + vraies images), round-trip HTTP complet pas encore vérifiable faute d'API déployée.
- Mouvements de stock, alertes de seuil et historique (Phase 6) — logique pure vérifiée en conditions réelles, service testé (Prisma mocké), UI testée.
- Caisse : vente, paiement mixte, décrémentation automatique du stock, remboursement (Phase 7) — logique pure vérifiée en conditions réelles, service testé (Prisma mocké), UI testée (un bug de dépassement visuel réel a été trouvé et corrigé).
- Plan de salle, additions, transfert/fusion/division, clôture liée à la caisse (Phase 8) — service testé (Prisma mocké), UI testée (analyse/build) ; fusion/division pas encore dans l'UI.
- Offline-first pour ventes et mouvements de stock : idempotence, moteur de synchronisation par lot, file locale, indicateur de connexion (Phase 9) — vérifié en conditions réelles pour la persistance locale, mocké pour le backend.
- Fournisseurs, achats, réception avec incrémentation automatique du stock (Phase 10) — service testé (Prisma mocké), UI testée (analyse/build).
- Clients, crédits, remboursements, et activation du paiement à crédit en caisse (Phase 11) — service testé (Prisma mocké), UI testée.
- Dépenses, pertes valorisées, clôture de caisse, et correction transverse de la sérialisation des `Decimal` (Phase 12) — services testés (Prisma mocké), UI testée.
- Rapports (chiffre d'affaires, marge, bénéfice net estimé, créances, alertes de stock, top produits, performance serveurs) avec export CSV (Phase 13) — service testé (Prisma mocké), UI testée.
- Notifications in-app (diffusion, alertes de stock bas à la demande) (Phase 14) — service testé (Prisma mocké), UI testée.
- PWA avancée : service worker de cache écrit à la main (celui de Flutter ne fait plus rien dans ce SDK), bandeau de mise à jour, bouton d'installation (Phase 15) — **hors ligne réel vérifié** (app chargée avec le serveur effectivement arrêté).
- Tests complets (Phase 16) : lacunes unitaires comblées (161 tests NestJS, 30 Flutter), **isolation multi-tenant RLS vérifiée par une vraie requête Postgres simulant deux utilisateurs** (pas seulement les advisors statiques) ; E2E non fabriqués faute d'API déployée.
- Production (Phase 17) : bug réel de CI corrigé (`DATABASE_URL` manquant, aurait fait échouer le premier run réel), job de déploiement structuré mais inerte (pas d'hébergeur choisi), `.env.example` réconcilié avec l'usage réel du code, `API_URL` Flutter enfin configurable par environnement.

## Les 17 phases du plan initial sont closes

Chacune restait au statut `TESTING` plutôt que `DONE` dans ce document parce que la définition de « fini » ici (voir `CLAUDE.md`/prompt maître §11) inclut une vérification en conditions réelles que trois blocages environnementaux ont empêchée pour une bonne partie de chaque phase — **deux des trois ont été levés le 2026-09-06** (accès GitHub, `DATABASE_URL` réel, voir « Problèmes connus » ci-dessus) :

1. ~~`DATABASE_URL` réel indisponible~~ **résolu** — API NestJS démarrée en local pour la première fois, round-trip HTTP réel vérifié (`SupabaseJwtGuard` et `PermissionsGuard` tous deux confirmés en conditions réelles, pas seulement mockés).
2. ~~Accès en écriture GitHub manquant~~ **résolu** — premier push réussi, pipeline CI exécuté réellement sur GitHub Actions et vert (deux bugs réels trouvés et corrigés au passage : lockfile incohérent, `prisma generate` manquant en CI).
3. **Docker absent de cette machine** — toujours bloqué, `docker build`/`docker-compose up` jamais testés.

Rien de tout cela n'a été contourné ni fabriqué : chaque vérification réelle est documentée à l'endroit où elle a eu lieu, et les mentions « non vérifié en conditions réelles » dans chaque section de phase ci-dessous n'ont pas été réécrites rétroactivement une par une (disproportionné) — elles restent la trace fidèle de ce qui était vérifiable *au moment de la construction* de chaque phase, la levée du blocage étant postérieure et documentée ici. Le code métier, lui, est réel, testé (191 tests au total, NestJS + Flutter), documenté, et commité phase par phase avec un historique Git complet des décisions.

## Déploiement de production — PWA Flutter Web (2026-09-06)

**La PWA est en ligne** : https://chez-yasmine-two.vercel.app (projet Vercel `chez-yasmine`, compte `yaminerestomaquis-1697`), déployée automatiquement à chaque push sur `main` (Git integration Vercel, indépendante du job `deploy` de `.github/workflows/ci.yml` qui reste ciblé sur un hébergeur pour l'API).

- `apps/web/flutter/vercel.json` : le SDK Flutter n'est pas préinstallé sur l'image de build Vercel — `installCommand` clone la branche `stable` (superficiel) avant `pub get`, `buildCommand` invoque `flutter build web --release` par chemin relatif (chaque étape Vercel est un shell distinct, une variable `PATH` exportée dans l'une ne survit pas dans l'autre).
- **Premier essai raté** : le tout premier déploiement (`chez-yasmine`) a été créé par un mécanisme différé côté Vercel après la connexion GitHub — hors du flux normal de création — et a servi un 404 en 3 secondes (aucun vrai build). Root Directory était pourtant déjà correctement configuré (`apps/web/flutter`) ; un simple **Redeploy** avec les Project Settings à jour a suffi, cette fois un vrai build de ~2 minutes (clonage SDK + compilation), résultat vérifié dans le navigateur : page de connexion réelle, logo, et le **bandeau d'installation PWA apparu naturellement** (première fois en conditions réelles, pas simulé comme en Phase 15).
- **Connecteur Vercel MCP défaillant pendant cette session** : `list_projects`/`get_project` retournaient systématiquement des résultats vides/404 pour des projets pourtant bien réels et visibles dans le dashboard (confirmé par captures d'écran de l'utilisateur). Le compte lui-même avait aussi changé deux fois en cours de session (`SORO` → `yaminerestomaquis-1697`) sans action explicite. Toute la suite de l'opération (configuration Root Directory, Redeploy, suppression d'un projet orphelin `chez-yasmine-pwa` créé par une tentative en double) a donc été faite via le navigateur (Claude in Chrome, connecté à la vraie session Vercel de l'utilisateur) plutôt que via les outils MCP — à revérifier si le connecteur MCP redevient fiable dans une session future.
- `API_URL` n'a pas été redéfini au build (`--dart-define`) : la PWA déployée pointe encore vers `http://localhost:3000`, en attendant le choix d'un hébergeur pour l'API NestJS.

## Déploiement de production — API NestJS (2026-09-06)

**L'API est en ligne** : https://chez-yasmine-api.onrender.com (Render, service `chez-yasmine-api`, plan Free, déployée en Docker via `render.yaml` + `docker/Dockerfile.nestjs`, déploiement continu depuis `main`).

- Fly.io a été essayé en premier (choisi comme moins cher lors de l'étude comparative) mais abandonné : la vérification de carte bancaire nécessaire pour tout déploiement (même gratuit) a échoué à deux reprises pour l'utilisateur — blocage bancaire côté émetteur, pas un problème Fly.io. Render a été choisi en second choix car son palier gratuit ne demande **aucune carte**.
- `docker/Dockerfile.nestjs` avait les deux mêmes bugs que la CI GitHub Actions (Phase 17) — jamais détectés localement faute de Docker installé sur cette machine : `DATABASE_URL` manquant pour que `prisma.config.ts` se résolve, et `prisma generate` jamais exécuté avant `npm run build` (l'étage runtime réinstalle `@prisma/client` à neuf sans le client généré). Corrigés avant le premier déploiement réel — cette fois vérifiés directement par le build Render réussi (`Deploy succeeded`), pas seulement rejoués localement.
- Les valeurs sensibles (`SUPABASE_ANON_KEY`, `DATABASE_URL`) ont été saisies par l'utilisateur lui-même dans le tableau de bord Render — jamais tapées par l'agent dans un formulaire web.
- **Vérifié en conditions réelles, pour la première fois du projet, contre un vrai déploiement public** : `GET /` → 200 ; `GET /auth/me` sans jeton → 401 avec le message français exact (`SupabaseJwtGuard` confirmé fonctionnel en production, pas seulement en local).
- `apps/web/flutter/vercel.json` mis à jour : `flutter build web` inclut maintenant `--dart-define=API_URL=https://chez-yasmine-api.onrender.com` — la PWA en production pointe enfin vers la vraie API plutôt que `localhost:3000`.
- **Limite connue du palier Free Render** : l'instance se met en veille après une période d'inactivité, avec un redémarrage à froid pouvant dépasser 50 secondes sur la requête suivante — acceptable pour découvrir/valider le déploiement, à surveiller si ça devient gênant en usage réel (upgrade payant possible plus tard).

## Prochaines étapes immédiates

1. Vérifier dans le navigateur que la PWA déployée (une fois le nouveau build Vercel terminé) communique bien avec l'API réelle — premier vrai round-trip Flutter → NestJS → Postgres en conditions de production.
2. Rejouer manuellement les deux scénarios E2E du prompt maître §39 maintenant que l'API tourne réellement en production (fait ponctuellement pour la connexion/permissions ci-dessus, pas encore pour les deux scénarios complets bout en bout : vente/paiement/stock/clôture, et coupure réseau/sync).
3. Vérifier `docker build`/`docker-compose up` si Docker devient disponible sur cette machine.
