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

### Phase 3 — Base de données — `TODO`
Modèle, migrations, relations, index, RLS, seeds. Non commencé (projet Supabase vierge).

### Phase 4 — Authentification et RBAC — `TODO`
Utilisateurs, organisations, établissements, rôles, permissions, sessions — via Supabase Auth + RBAC NestJS (décision actée).

### Phase 5 — Produits et photos — `TODO`
### Phase 6 — Stock — `TODO`
### Phase 7 — POS — `TODO`
### Phase 8 — Tables et serveurs — `TODO`
### Phase 9 — Offline-first — `TODO`
### Phase 10 — Achats / Fournisseurs — `TODO`
### Phase 11 — Clients / Crédits — `TODO`
### Phase 12 — Dépenses / Pertes / Comptabilité — `TODO`
### Phase 13 — Rapports — `TODO`
### Phase 14 — Notifications — `TODO`
### Phase 15 — PWA avancée — `TODO`
### Phase 16 — Tests complets — `TODO`
### Phase 17 — Production — `TODO`

## Fonctionnalités terminées

Aucune fonctionnalité métier v5 encore développée (Phase 0-2 = audit/fondations uniquement, conformément à la règle du prompt maître : pas de développement fonctionnel avant une base technique saine).

## Prochaines étapes immédiates

1. Résoudre l'accès en écriture au dépôt GitHub distant (`yasminerestomaquis/Chez_Yasmine`) avant tout `git push`.
2. Premier commit + push, puis vérifier que le pipeline CI GitHub Actions passe.
3. Démarrer la Phase 3 (modèle de données Supabase) : schéma multi-tenant, migrations initiales, RLS.
