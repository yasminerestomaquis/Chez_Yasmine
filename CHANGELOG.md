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
- Schéma de base de données complet (30 tables) appliqué sur Supabase via 6 migrations versionnées (`supabase/migrations/`), avec RLS multi-tenant sur toutes les tables et advisors sécurité/performance vérifiés (voir `docs/database/schema.md`).
- Seed des rôles/permissions système (`supabase/seed/001_roles_permissions.sql`) : 15 permissions, 8 rôles, 74 associations.
- Prisma 7 intégré dans NestJS (`prisma.config.ts`, `apps/api/nestjs/prisma/schema.prisma`, `PrismaModule`/`PrismaService` via adaptateur `@prisma/adapter-pg`).

### Décisions
- Adoption de l'architecture v5 (Flutter + NestJS + Supabase) en remplacement du prototype v1 local (React/Vite/Dexie), conservé comme référence.
- Authentification via Supabase Auth uniquement.
- RLS activée et testée sur toutes les tables comme défense en profondeur, en plus du filtrage applicatif NestJS.
- `@nestjs/mau` désinstallé (non utilisé, source de 5 des 9 vulnérabilités `npm audit` initiales).
