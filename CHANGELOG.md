# Changelog — Chez Yasmine

## [Unreleased]

### Ajouté
- Structure monorepo v5 (`apps/`, `packages/`, `supabase/`, `docs/*`, `docker/`, `.github/workflows/`).
- Scaffold NestJS (`apps/api/nestjs`), build vérifié.
- Scaffold Flutter Web (`apps/web/flutter`), `flutter analyze`/`flutter test`/`flutter build web` vérifiés.
- SDK Flutter installé localement (`C:\flutter`, clonage du dépôt officiel, branche stable).
- Scaffold Supabase local (`supabase/config.toml`, dossiers `migrations/`, `functions/`, `seed/`).
- Documentation de gouvernance : `CLAUDE.md`, `ARCHITECTURE.md`, `PROJECT_PLAN.md`, `README.md`.
- `.env.example`, `.gitignore`, `Dockerfile.nestjs`, `docker-compose.yml`, workflow CI GitHub Actions (NestJS + Flutter).
- Remote GitHub `origin` configuré vers `https://github.com/yasminerestomaquis/Chez_Yasmine.git` (push encore bloqué, voir `PROJECT_PLAN.md`).
- Branding **Chez Yasmine** : logo top-left dans l'app v1 (prototype) et dans l'app Flutter v5, manifest PWA, favicon, icônes générées depuis `Chez Yasmine.png`.

### Décisions
- Adoption de l'architecture v5 (Flutter + NestJS + Supabase) en remplacement du prototype v1 local (React/Vite/Dexie), conservé comme référence.
- Authentification via Supabase Auth uniquement.
