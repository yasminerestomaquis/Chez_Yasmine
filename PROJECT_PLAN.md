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

- **BLOCKED (permissions)** — Push vers `origin` impossible : le compte `gh`/git authentifié (`Autocad-Qgis`) n'a pas les droits d'écriture sur `yasminerestomaquis/Chez_Yasmine`. Rien n'a été poussé.
- **Outillage local manquant** — Docker n'est pas installé sur la machine de développement (le build de `docker/Dockerfile.nestjs` n'a donc pas pu être testé localement). Supabase CLI n'est pas installée globalement mais reste utilisable à la demande via `npx supabase@latest ...` (a servi à générer `supabase/config.toml`) ; le développement contre le projet Supabase distant se fait surtout via les outils MCP Supabase (migrations, SQL, Storage) plutôt que via `supabase start` (qui nécessite Docker).
- Un test (`AdditionDetail.test.tsx`, prototype v1) est occasionnellement flaky sous charge (timeout `findByText`) mais passe de manière fiable en isolation ou en re-run — sans impact sur le v5, noté pour mémoire.
- **`npm audit` — 4 vulnérabilités high acceptées** dans `apps/api/nestjs` : `deepmerge-ts`/`mysql2` sont des dépendances transitives du *CLI* Prisma 7.10.0 lui-même (`@prisma/config`), pas du client généré ni du code applicatif — non exposées en production. Le correctif proposé par `npm audit fix --force` rétrograderait vers `prisma@6.19.3`, ce qui abandonnerait la CLI stable actuelle pour une version antérieure ; à réévaluer à la prochaine release stable de Prisma. `@nestjs/mau` (CLI de déploiement Nest, non utilisé — on déploie via Docker/GitHub Actions) a été désinstallé, ce qui a déjà éliminé 5 des 9 vulnérabilités initiales.
- `DATABASE_URL` réel (mot de passe de connexion directe Postgres) non disponible dans cet environnement : les migrations ont été appliquées via les outils MCP Supabase (API de gestion), pas via une connexion Postgres directe depuis la machine. `prisma db pull`/`prisma migrate dev` et toute exécution réelle de l'API NestJS contre la base nécessitent de renseigner ce mot de passe dans `.env`.

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

### Phase 13 — Rapports — `TODO`
### Phase 14 — Notifications — `TODO`
### Phase 15 — PWA avancée — `TODO`
### Phase 16 — Tests complets — `TODO`
### Phase 17 — Production — `TODO`

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

## Prochaines étapes immédiates

1. Résoudre l'accès en écriture au dépôt GitHub distant (`yasminerestomaquis/Chez_Yasmine`) avant tout `git push`.
2. Premier commit + push, puis vérifier que le pipeline CI GitHub Actions passe.
3. Renseigner le mot de passe de connexion Postgres réel dans `.env` pour vérifier tous les modules en conditions réelles et pouvoir lancer l'API NestJS localement.
4. Démarrer la Phase 13 (Rapports).
